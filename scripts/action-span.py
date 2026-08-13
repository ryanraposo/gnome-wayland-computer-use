#!/usr/bin/env python3
"""Execute an already-decided Cua action span behind one model/tool boundary.

This is intentionally a composition layer, not a second control plane. Every
operation is still executed by Cua Driver. The model supplies the whole span
once; this process keeps one Cua MCP session open and returns only when the span
finishes or Cua reports the first genuine boundary.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import selectors
import shutil
import subprocess
import sys
import time
from typing import Any

SCHEMA = "gwcu.action-span.v1"
REQUEST_SCHEMA = "gwcu.action-span.request.v1"
PROTOCOL = "2024-11-05"
MAX_ACTIONS = 64


def compact(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True)


def resolve_driver(explicit: str | None) -> str | None:
    if explicit:
        return explicit
    env = os.environ.get("CUA_DRIVER_BIN")
    if env:
        return env
    found = shutil.which("cua-driver")
    if found:
        return found
    candidate = Path.home() / ".local/bin/cua-driver"
    return str(candidate) if candidate.is_file() and os.access(candidate, os.X_OK) else None


def send(proc: subprocess.Popen[str], payload: dict[str, Any]) -> None:
    assert proc.stdin is not None
    proc.stdin.write(compact(payload) + "\n")
    proc.stdin.flush()


def recv_for(proc: subprocess.Popen[str], request_id: int, timeout: float) -> dict[str, Any]:
    assert proc.stdout is not None
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    deadline = time.monotonic() + timeout
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise TimeoutError(f"timed out waiting for MCP response id={request_id}")
            line = proc.stdout.readline()
            if not line:
                raise RuntimeError("cua-driver MCP exited before responding")
            msg = json.loads(line)
            if msg.get("id") == request_id:
                return msg
    finally:
        selector.close()


def normalize_result(result: Any) -> Any:
    if not isinstance(result, dict):
        return result
    structured = result.get("structuredContent")
    if structured is None:
        structured = result.get("structured_content")
    if structured is not None:
        return structured
    return result.get("content", result)


def explicit_boundary(response: dict[str, Any]) -> tuple[bool, str | None]:
    if "error" in response:
        return True, "mcp_error"
    result = response.get("result")
    if not isinstance(result, dict):
        return True, "invalid_result"
    if result.get("isError") is True:
        return True, "cua_error"
    structured = result.get("structuredContent")
    if structured is None:
        structured = result.get("structured_content")
    if isinstance(structured, dict):
        if structured.get("ok") is False or structured.get("success") is False:
            return True, "cua_failure"
        if structured.get("refused") is True:
            return True, "cua_refusal"
    return False, None


def parse_actions(raw: str) -> list[dict[str, Any]]:
    value = json.loads(raw)
    if isinstance(value, dict):
        if value.get("schema") not in (None, REQUEST_SCHEMA):
            raise ValueError("unsupported request schema")
        value = value.get("actions")
    if not isinstance(value, list) or not value:
        raise ValueError("actions must be a non-empty JSON array")
    if len(value) > MAX_ACTIONS:
        raise ValueError(f"action span exceeds {MAX_ACTIONS} actions")
    actions: list[dict[str, Any]] = []
    for index, action in enumerate(value):
        if not isinstance(action, dict):
            raise ValueError(f"action {index} must be an object")
        name = action.get("name")
        arguments = action.get("arguments", {})
        if not isinstance(name, str) or not name.strip():
            raise ValueError(f"action {index} requires a name")
        if not isinstance(arguments, dict):
            raise ValueError(f"action {index} arguments must be an object")
        actions.append({"name": name, "arguments": arguments})
    return actions


def envelope(ok: bool, code: str, *, requested: int = 0, completed: int = 0,
             results: list[dict[str, Any]] | None = None, boundary: dict[str, Any] | None = None,
             detail: str | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "schema": SCHEMA,
        "ok": ok,
        "code": code,
        "requested": requested,
        "completed": completed,
        "results": results or [],
        "boundary": boundary,
    }
    if detail:
        payload["detail"] = detail
    return payload


def run(driver: str, actions: list[dict[str, Any]], timeout: float) -> tuple[dict[str, Any], int]:
    try:
        proc = subprocess.Popen(
            [driver, "mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except OSError as exc:
        return envelope(False, "driver_unavailable", requested=len(actions), detail=str(exc)), 50

    results: list[dict[str, Any]] = []
    try:
        send(proc, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL,
                "capabilities": {},
                "clientInfo": {"name": "gwcu-action-span", "version": "2.3.0"},
            },
        })
        init = recv_for(proc, 1, timeout)
        if "error" in init or not isinstance(init.get("result"), dict):
            return envelope(False, "mcp_initialize_failed", requested=len(actions), detail=compact(init)), 50
        send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        for index, action in enumerate(actions):
            request_id = index + 2
            send(proc, {
                "jsonrpc": "2.0", "id": request_id, "method": "tools/call",
                "params": {"name": action["name"], "arguments": action["arguments"]},
            })
            response = recv_for(proc, request_id, timeout)
            result = normalize_result(response.get("result"))
            is_boundary, reason = explicit_boundary(response)
            results.append({"index": index, "name": action["name"], "result": result})
            if is_boundary:
                return envelope(
                    False,
                    "boundary",
                    requested=len(actions),
                    completed=index,
                    results=results,
                    boundary={"index": index, "name": action["name"], "reason": reason},
                ), 30

        return envelope(True, "completed", requested=len(actions), completed=len(actions), results=results), 0
    except (TimeoutError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        return envelope(False, "transport_boundary", requested=len(actions), completed=len(results),
                        results=results, detail=str(exc)), 50
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=1)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--driver", help="cua-driver executable path")
    parser.add_argument("--timeout", type=float, default=15.0, help="seconds allowed for each Cua operation")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--actions-json", help="JSON action array or gwcu.action-span.request.v1 object")
    group.add_argument("--stdin", action="store_true", help="read the request JSON from stdin")
    args = parser.parse_args()

    raw = sys.stdin.read() if args.stdin else args.actions_json
    assert raw is not None
    try:
        actions = parse_actions(raw)
    except (ValueError, json.JSONDecodeError) as exc:
        print(compact(envelope(False, "invalid_request", detail=str(exc))))
        return 2

    driver = resolve_driver(args.driver)
    if not driver:
        print(compact(envelope(False, "driver_missing", requested=len(actions))))
        return 50

    payload, rc = run(driver, actions, max(1.0, min(args.timeout, 120.0)))
    print(compact(payload))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
