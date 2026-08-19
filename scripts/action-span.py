#!/usr/bin/env python3
"""Execute a Cua/WORLDLINE transaction behind one model/tool boundary."""
from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
from pathlib import Path
from typing import Any

from mcp_client import recv_for, resolve_driver, send

SCHEMA = "gwcu.action-span.v1"
REQUEST_SCHEMA = "gwcu.action-span.request.v1"
TRANSACTION_SCHEMA = "gwcu.transaction.v1"
CONTROL_SCHEMA = "gwcu.control-priority.v2"
PROTOCOL = "2024-11-05"
MAX_ACTIONS = 64
MAX_TRANSITIONS = 256
MAX_RESPONSE = 1 << 20
_TRUE = {"on", "yes", "true", "1", "background"}


def compact(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True)


def standing_preference() -> tuple[str, str]:
    raw = os.getenv("GWCU_BACKGROUND_PRIORITY")
    if raw is not None:
        return ("background" if raw.casefold() in _TRUE else "foreground", "environment")

    path = (
        Path(os.getenv("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        / "gnome-wayland-computer-use"
        / "background-priority"
    )
    try:
        raw = path.read_text().strip().casefold()
    except OSError:
        raw = "off"
    return (
        "background" if raw in _TRUE else "foreground",
        "saved" if path.is_file() else "default",
    )


def resolve_control(control: dict[str, Any]) -> dict[str, Any]:
    """Resolve delivery mechanically; never infer background from missing cues.

    ``foreground_confidence`` is retained only so older callers do not break.
    It is deliberately non-authoritative: treating "no foreground words" as
    confidence zero was the bug that made an OFF preference execute invisibly.
    """
    preference, source = standing_preference()
    explicit = control.get("explicit_mode")
    visible_required = bool(control.get("visible_required", False))
    legacy_confidence = control.get("foreground_confidence")

    if explicit in {"background", "foreground"}:
        mode = explicit
        reason = "explicit_intent"
    elif visible_required:
        mode = "foreground"
        reason = "visible_result"
    else:
        mode = preference
        reason = "standing_preference"

    contradicts = mode != preference
    return {
        "schema": CONTROL_SCHEMA,
        "mode": mode,
        "reason": reason,
        "standing_preference": preference,
        "preference_source": source,
        "visible_required": visible_required,
        "legacy_foreground_confidence": legacy_confidence,
        "legacy_confidence_authoritative": False,
        "contradicts_preference": contradicts,
        "notice": (
            "Doing that now — switching to foreground. OK?"
            if contradicts and mode == "foreground"
            else None
        ),
        "extra_model_calls": 0,
    }


def worldline_socket(value: str | None) -> Path:
    if value:
        return Path(value)
    runtime = os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return Path(runtime) / "gnome-wayland-computer-use" / "worldline.sock"


def worldline_call(path: Path, payload: dict[str, Any], timeout: float) -> dict[str, Any]:
    client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    client.settimeout(timeout)
    try:
        client.connect(str(path))
        client.sendall((compact(payload) + "\n").encode())
        data = bytearray()
        while b"\n" not in data and len(data) <= MAX_RESPONSE:
            chunk = client.recv(65536)
            if not chunk:
                break
            data.extend(chunk)
    finally:
        client.close()
    if not data:
        raise RuntimeError("WORLDLINE closed without response")
    return json.loads(bytes(data).split(b"\n", 1)[0])


def structured(response: dict[str, Any]) -> dict[str, Any] | None:
    result = response.get("result") if isinstance(response, dict) else None
    if not isinstance(result, dict):
        return None
    value = result.get("structuredContent", result.get("structured_content"))
    return value if isinstance(value, dict) else None


def normalize_result(response: dict[str, Any]) -> Any:
    result = response.get("result") if isinstance(response, dict) else None
    if not isinstance(result, dict):
        return result
    value = structured(response)
    return value if value is not None else result.get("content", result)


def boundary(response: dict[str, Any]) -> tuple[bool, str | None]:
    if "error" in response:
        return True, "mcp_error"
    result = response.get("result")
    if not isinstance(result, dict):
        return True, "invalid_result"
    if result.get("isError") is True:
        return True, "cua_error"
    value = structured(response)
    if value and (value.get("ok") is False or value.get("success") is False):
        return True, "cua_failure"
    if value and value.get("refused") is True:
        return True, "cua_refusal"
    return False, None


def background_unavailable(response: dict[str, Any]) -> bool:
    blob = compact(structured(response) or {}).casefold()
    return any(
        marker in blob
        for marker in (
            "background_unavailable",
            "background unavailable",
            "foreground_required",
            "foreground required",
        )
    )


def normalize_action(raw: dict[str, Any], index: int) -> dict[str, Any]:
    name = raw.get("name")
    arguments = raw.get("arguments", {})
    if not isinstance(name, str) or not name.strip():
        raise ValueError(f"action {index} requires a name")
    if not isinstance(arguments, dict):
        raise ValueError(f"action {index} arguments must be an object")
    return {"name": name, "arguments": arguments}


def normalize_control(value: Any) -> dict[str, Any]:
    if value is None:
        return {}
    if not isinstance(value, dict):
        raise ValueError("control must be an object")

    confidence = value.get("foreground_confidence")
    explicit = value.get("explicit_mode")
    visible = value.get("visible_required", False)

    if confidence is not None and (
        not isinstance(confidence, (int, float))
        or isinstance(confidence, bool)
        or not 0 <= float(confidence) <= 1
    ):
        raise ValueError("foreground_confidence must be 0..1")
    if explicit not in (None, "background", "foreground"):
        raise ValueError("explicit_mode must be background|foreground")
    if not isinstance(visible, bool):
        raise ValueError("visible_required must be a boolean")

    return {
        "foreground_confidence": None if confidence is None else float(confidence),
        "explicit_mode": explicit,
        "visible_required": visible,
    }


def start_index(value: Any, size: int) -> int:
    if value is None:
        return 0
    if not isinstance(value, int) or isinstance(value, bool) or not 0 <= value < size:
        raise ValueError(f"start must be an integer in 0..{size - 1}")
    return value


def valid_target(target: Any, size: int) -> bool:
    if isinstance(target, int) and not isinstance(target, bool):
        return 0 <= target < size
    if isinstance(target, dict):
        return all(
            isinstance(value, int)
            and not isinstance(value, bool)
            and 0 <= value < size
            for value in target.values()
        )
    return False


def parse_request(raw: str) -> dict[str, Any]:
    value = json.loads(raw)
    if isinstance(value, list):
        value = {"schema": REQUEST_SCHEMA, "actions": value}
    if not isinstance(value, dict) or value.get("schema") not in (
        None,
        REQUEST_SCHEMA,
        TRANSACTION_SCHEMA,
    ):
        raise ValueError("unsupported request schema")

    control = normalize_control(value.get("control"))
    steps = value.get("steps")
    if steps is not None:
        if not isinstance(steps, list) or not steps or len(steps) > MAX_ACTIONS:
            raise ValueError("invalid steps")
        parsed = []
        for index, step in enumerate(steps):
            if not isinstance(step, dict):
                raise ValueError(f"step {index} must be an object")
            action = step.get("action", step if "name" in step else None)
            if not isinstance(action, dict):
                raise ValueError(f"step {index} requires action")
            item: dict[str, Any] = {"action": normalize_action(action, index)}
            if "await" in step:
                if not isinstance(step["await"], dict):
                    raise ValueError(f"step {index} await must be an object")
                item["await"] = step["await"]
            if "next" in step:
                if not valid_target(step["next"], len(steps)):
                    raise ValueError(
                        f"step {index} next targets must be indices in 0..{len(steps) - 1}"
                    )
                item["next"] = step["next"]
            parsed.append(item)
        return {
            "schema": TRANSACTION_SCHEMA,
            "steps": parsed,
            "start": start_index(value.get("start"), len(parsed)),
            "control": control,
        }

    actions = value.get("actions")
    if not isinstance(actions, list) or not actions or len(actions) > MAX_ACTIONS:
        raise ValueError("actions must be a non-empty bounded array")
    parsed = [{"action": normalize_action(action, index)} for index, action in enumerate(actions)]
    return {
        "schema": REQUEST_SCHEMA,
        "steps": parsed,
        "start": start_index(value.get("start"), len(parsed)),
        "control": control,
    }


def envelope(ok: bool, code: str, **kwargs: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "schema": SCHEMA,
        "ok": ok,
        "code": code,
        "requested": kwargs.get("requested", 0),
        "completed": kwargs.get("completed", 0),
        "results": kwargs.get("results", []),
        "boundary": kwargs.get("boundary"),
    }
    for key in ("detail", "revision", "control"):
        if kwargs.get(key) is not None:
            payload[key] = kwargs[key]
    return payload


def next_index(step: dict[str, Any], current: int, wait_result: dict[str, Any] | None, total: int) -> int:
    target_spec = step.get("next")
    if isinstance(target_spec, int):
        target = target_spec
    elif isinstance(target_spec, dict):
        branch = (wait_result or {}).get("matched_branch")
        if branch in target_spec:
            target = int(target_spec[branch])
        elif "default" in target_spec:
            target = int(target_spec["default"])
        elif branch is not None:
            raise RuntimeError(f"no next target for branch {branch}")
        else:
            return current + 1
    else:
        return current + 1
    if not 0 <= target < total:
        raise ValueError(f"next target {target} out of range 0..{total - 1}")
    return target


def tool_modes(response: dict[str, Any]) -> dict[str, bool]:
    supported: dict[str, bool] = {}
    result = response.get("result") if isinstance(response, dict) else None
    tools = result.get("tools", []) if isinstance(result, dict) else []
    for tool in tools:
        if not isinstance(tool, dict) or not isinstance(tool.get("name"), str):
            continue
        schema = tool.get("inputSchema", tool.get("input_schema", {}))
        properties = schema.get("properties", {}) if isinstance(schema, dict) else {}
        if isinstance(properties, dict) and "delivery_mode" in properties:
            supported[tool["name"]] = True
    return supported


def run(driver: str, request: dict[str, Any], timeout: float, worldline_path: Path):
    steps = request["steps"]
    requested = len(steps)
    control = resolve_control(request.get("control", {}))
    overrides: list[dict[str, Any]] = []

    try:
        process = subprocess.Popen(
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
        return envelope(
            False,
            "driver_unavailable",
            requested=requested,
            detail=str(exc),
            control=control,
        ), 50

    results: list[dict[str, Any]] = []
    completed = 0
    last_revision = None
    try:
        send(
            process,
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": PROTOCOL,
                    "capabilities": {},
                    "clientInfo": {"name": "gwcu-action-span", "version": "2.3.0"},
                },
            },
        )
        initialized = recv_for(process, 1, timeout)
        if "error" in initialized:
            return envelope(
                False,
                "mcp_initialize_failed",
                requested=requested,
                detail=compact(initialized),
                control=control,
            ), 50

        send(process, {"jsonrpc": "2.0", "method": "notifications/initialized"})
        send(process, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        try:
            modes = tool_modes(recv_for(process, 2, min(timeout, 5)))
        except Exception:
            modes = {}

        index = request["start"]
        transition = 0
        request_id = 3
        while 0 <= index < requested:
            transition += 1
            if transition > MAX_TRANSITIONS:
                return envelope(
                    False,
                    "boundary",
                    requested=requested,
                    completed=completed,
                    results=results,
                    boundary={"index": index, "reason": "transition_limit"},
                    control=control,
                ), 30

            step = steps[index]
            action = step["action"]
            baseline = last_revision
            if "await" in step:
                try:
                    status = worldline_call(worldline_path, {"op": "status"}, 3)
                    baseline = status.get("revision", baseline) if status.get("ok") else baseline
                except Exception as exc:
                    return envelope(
                        False,
                        "worldline_boundary",
                        requested=requested,
                        completed=completed,
                        results=results,
                        boundary={"index": index, "reason": "worldline_unavailable_before_action"},
                        detail=str(exc),
                        revision=last_revision,
                        control=control,
                    ), 50

            arguments = dict(action["arguments"])
            supports_delivery = bool(modes.get(action["name"]))
            applied = None
            if supports_delivery and "delivery_mode" not in arguments:
                arguments["delivery_mode"] = control["mode"]
                applied = control["mode"]
            elif "delivery_mode" in arguments:
                applied = arguments["delivery_mode"]

            send(
                process,
                {
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "method": "tools/call",
                    "params": {"name": action["name"], "arguments": arguments},
                },
            )
            response = recv_for(process, request_id, timeout)
            request_id += 1

            fallback = False
            if applied == "background" and supports_delivery and background_unavailable(response):
                fallback = True
                overrides.append(
                    {
                        "index": index,
                        "from": "background",
                        "to": "foreground",
                        "reason": "cua_background_unavailable",
                    }
                )
                arguments["delivery_mode"] = "foreground"
                send(
                    process,
                    {
                        "jsonrpc": "2.0",
                        "id": request_id,
                        "method": "tools/call",
                        "params": {"name": action["name"], "arguments": arguments},
                    },
                )
                response = recv_for(process, request_id, timeout)
                request_id += 1

            result = normalize_result(response)
            failed, reason = boundary(response)
            record = {
                "index": index,
                "name": action["name"],
                "result": result,
                "control": {
                    "requested": control["mode"],
                    "delivery_mode_supported": supports_delivery,
                    "applied": arguments.get("delivery_mode") if supports_delivery else "driver_default",
                    "fallback": fallback,
                },
            }
            results.append(record)
            if failed:
                control["runtime_overrides"] = overrides
                return envelope(
                    False,
                    "boundary",
                    requested=requested,
                    completed=completed,
                    results=results,
                    boundary={"index": index, "name": action["name"], "reason": reason},
                    revision=last_revision,
                    control=control,
                ), 30

            completed += 1
            wait_result = None
            if "await" in step:
                spec = dict(step["await"])
                spec["op"] = "wait"
                if baseline is not None:
                    spec.setdefault("after_revision", baseline)
                try:
                    wait_result = worldline_call(
                        worldline_path,
                        spec,
                        max(1, min(float(spec.get("timeout_ms", 5000)) / 1000 + 2, 122)),
                    )
                except Exception as exc:
                    return envelope(
                        False,
                        "worldline_boundary",
                        requested=requested,
                        completed=completed,
                        results=results,
                        boundary={"index": index, "reason": "worldline_unavailable"},
                        detail=str(exc),
                        revision=last_revision,
                        control=control,
                    ), 50
                record["worldline"] = wait_result
                last_revision = wait_result.get("revision", last_revision)
                if not wait_result.get("ok"):
                    return envelope(
                        False,
                        "boundary",
                        requested=requested,
                        completed=completed,
                        results=results,
                        boundary={
                            "index": index,
                            "reason": f"worldline_{wait_result.get('code', 'failure')}",
                        },
                        revision=last_revision,
                        control=control,
                    ), 30

            index = next_index(step, index, wait_result, requested)

        control["runtime_overrides"] = overrides
        control["runtime_notice"] = "Had to switch to foreground for this." if overrides else None
        return envelope(
            True,
            "completed",
            requested=requested,
            completed=completed,
            results=results,
            revision=last_revision,
            control=control,
        ), 0
    except Exception as exc:
        return envelope(
            False,
            "transport_boundary",
            requested=requested,
            completed=completed,
            results=results,
            detail=str(exc),
            revision=last_revision,
            control=control,
        ), 50
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--driver")
    parser.add_argument("--worldline-socket")
    parser.add_argument("--timeout", type=float, default=15)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--actions-json")
    group.add_argument("--stdin", action="store_true")
    args = parser.parse_args()
    raw = sys.stdin.read() if args.stdin else args.actions_json

    try:
        request = parse_request(raw)
    except Exception as exc:
        print(compact(envelope(False, "invalid_request", detail=str(exc))))
        return 2

    driver = resolve_driver(args.driver)
    if not driver:
        print(compact(envelope(False, "driver_missing", requested=len(request["steps"]))))
        return 50

    output, rc = run(
        driver,
        request,
        max(1, min(args.timeout, 120)),
        worldline_socket(args.worldline_socket),
    )
    print(compact(output))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
