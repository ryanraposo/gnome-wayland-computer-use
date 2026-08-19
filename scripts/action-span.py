#!/usr/bin/env python3
"""Execute a Cua/WORLDLINE transaction behind one model/tool boundary.

On supported GNOME, foreground input is admitted only after the exact
(pid, window_id) is persistently presented through Cua's attested GNOME helper.
No presentation proof means no input.
"""
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
CONTROL_SCHEMA = "gwcu.control-priority.v3"
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
    path = Path(os.getenv("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "gnome-wayland-computer-use" / "background-priority"
    try:
        raw = path.read_text().strip().casefold()
    except OSError:
        raw = "off"
    return ("background" if raw in _TRUE else "foreground", "saved" if path.is_file() else "default")


def resolve_control(control: dict[str, Any]) -> dict[str, Any]:
    preference, source = standing_preference()
    explicit = control.get("explicit_mode")
    visible_required = bool(control.get("visible_required", False))
    legacy_confidence = control.get("foreground_confidence")
    if explicit in {"background", "foreground"}:
        mode, reason = explicit, "explicit_intent"
    elif visible_required:
        mode, reason = "foreground", "visible_result"
    else:
        mode, reason = preference, "standing_preference"
    contradicts = mode != preference
    return {
        "schema": CONTROL_SCHEMA,
        "mode": mode,
        "reason": reason,
        "standing_preference": preference,
        "preference_source": source,
        "visible_required": visible_required,
        "foreground_contract": "exact_pid_window -> cua_gnome_present -> focused_visible_proof -> cua_input" if mode == "foreground" else "exact_target_background_where_supported",
        "legacy_foreground_confidence": legacy_confidence,
        "legacy_confidence_authoritative": False,
        "contradicts_preference": contradicts,
        "notice": "Doing that now — switching to foreground. OK?" if contradicts and mode == "foreground" else None,
        "extra_model_calls": 0,
    }


def worldline_socket(value: str | None) -> Path:
    if value:
        return Path(value)
    return Path(os.getenv("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "gnome-wayland-computer-use" / "worldline.sock"


def presenter_path(value: str | None) -> Path:
    return Path(value) if value else Path(__file__).resolve().with_name("present-window.py")


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


def exact_target(arguments: dict[str, Any]) -> tuple[int, int] | None:
    pid, window_id = arguments.get("pid"), arguments.get("window_id")
    if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0 and isinstance(window_id, int) and not isinstance(window_id, bool) and 0 <= window_id <= (1 << 32) - 1:
        return pid, window_id
    return None


def present_exact(path: Path, target: tuple[int, int], timeout: float) -> dict[str, Any]:
    pid, window_id = target
    try:
        proc = subprocess.run(
            [sys.executable, str(path), "present", "--pid", str(pid), "--window-id", str(window_id), "--timeout-ms", str(max(100, min(int(timeout * 1000), 3000)))],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=max(2.0, min(timeout + 1.0, 5.0)),
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "code": "presentation_transport_failed", "detail": str(exc)}
    try:
        value = json.loads(proc.stdout.strip()) if proc.stdout.strip() else {}
    except json.JSONDecodeError:
        value = {"ok": False, "code": "presentation_invalid_output", "detail": proc.stdout[:1024]}
    if proc.returncode != 0 and value.get("ok") is not False:
        value = {"ok": False, "code": "presentation_failed", "detail": proc.stderr[:1024]}
    return value


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
    return structured(response) or result.get("content", result)


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
    return any(x in blob for x in ("background_unavailable", "background unavailable", "foreground_required", "foreground required"))


def normalize_action(raw: dict[str, Any], index: int) -> dict[str, Any]:
    name, arguments = raw.get("name"), raw.get("arguments", {})
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
    if confidence is not None and (not isinstance(confidence, (int, float)) or isinstance(confidence, bool) or not 0 <= float(confidence) <= 1):
        raise ValueError("foreground_confidence must be 0..1")
    if explicit not in (None, "background", "foreground"):
        raise ValueError("explicit_mode must be background|foreground")
    if not isinstance(visible, bool):
        raise ValueError("visible_required must be a boolean")
    return {"foreground_confidence": None if confidence is None else float(confidence), "explicit_mode": explicit, "visible_required": visible}


def valid_target(target: Any, size: int) -> bool:
    if isinstance(target, int) and not isinstance(target, bool):
        return 0 <= target < size
    return isinstance(target, dict) and all(isinstance(v, int) and not isinstance(v, bool) and 0 <= v < size for v in target.values())


def parse_request(raw: str) -> dict[str, Any]:
    value = json.loads(raw)
    if isinstance(value, list):
        value = {"schema": REQUEST_SCHEMA, "actions": value}
    if not isinstance(value, dict) or value.get("schema") not in (None, REQUEST_SCHEMA, TRANSACTION_SCHEMA):
        raise ValueError("unsupported request schema")
    control = normalize_control(value.get("control"))
    source = value.get("steps") if value.get("steps") is not None else value.get("actions")
    if not isinstance(source, list) or not source or len(source) > MAX_ACTIONS:
        raise ValueError("actions/steps must be a non-empty bounded array")
    transaction = value.get("steps") is not None
    steps: list[dict[str, Any]] = []
    for index, raw_step in enumerate(source):
        if not isinstance(raw_step, dict):
            raise ValueError(f"step {index} must be an object")
        raw_action = raw_step.get("action", raw_step if not transaction else None)
        if not isinstance(raw_action, dict):
            raise ValueError(f"step {index} requires action")
        step: dict[str, Any] = {"action": normalize_action(raw_action, index)}
        if transaction and "await" in raw_step:
            if not isinstance(raw_step["await"], dict):
                raise ValueError(f"step {index} await must be an object")
            step["await"] = raw_step["await"]
        if transaction and "next" in raw_step:
            if not valid_target(raw_step["next"], len(source)):
                raise ValueError(f"step {index} next target out of range")
            step["next"] = raw_step["next"]
        steps.append(step)
    start = value.get("start", 0)
    if not isinstance(start, int) or isinstance(start, bool) or not 0 <= start < len(steps):
        raise ValueError("invalid start")
    return {"schema": TRANSACTION_SCHEMA if transaction else REQUEST_SCHEMA, "steps": steps, "start": start, "control": control}


def envelope(ok: bool, code: str, **kwargs: Any) -> dict[str, Any]:
    payload: dict[str, Any] = {"schema": SCHEMA, "ok": ok, "code": code, "requested": kwargs.get("requested", 0), "completed": kwargs.get("completed", 0), "results": kwargs.get("results", []), "boundary": kwargs.get("boundary")}
    for key in ("detail", "revision", "control"):
        if kwargs.get(key) is not None:
            payload[key] = kwargs[key]
    return payload


def next_index(step: dict[str, Any], current: int, wait_result: dict[str, Any] | None, total: int) -> int:
    spec = step.get("next")
    if isinstance(spec, int):
        target = spec
    elif isinstance(spec, dict):
        branch = (wait_result or {}).get("matched_branch")
        if branch in spec:
            target = int(spec[branch])
        elif "default" in spec:
            target = int(spec["default"])
        elif branch is not None:
            raise RuntimeError(f"no next target for branch {branch}")
        else:
            return current + 1
    else:
        return current + 1
    if not 0 <= target < total:
        raise ValueError(f"next target {target} out of range")
    return target


def tool_modes(response: dict[str, Any]) -> dict[str, bool]:
    result = response.get("result") if isinstance(response, dict) else None
    tools = result.get("tools", []) if isinstance(result, dict) else []
    supported: dict[str, bool] = {}
    for tool in tools:
        if not isinstance(tool, dict) or not isinstance(tool.get("name"), str):
            continue
        schema = tool.get("inputSchema", tool.get("input_schema", {}))
        props = schema.get("properties", {}) if isinstance(schema, dict) else {}
        if isinstance(props, dict) and "delivery_mode" in props:
            supported[tool["name"]] = True
    return supported


def fail_boundary(control: dict[str, Any], presentations: list[dict[str, Any]], requested: int, completed: int, results: list[dict[str, Any]], reason: str, *, index: Any = None, name: str | None = None, detail: str | None = None, revision: Any = None) -> tuple[dict[str, Any], int]:
    control["presentations"] = presentations
    b: dict[str, Any] = {"reason": reason}
    if index is not None:
        b["index"] = index
    if name is not None:
        b["name"] = name
    return envelope(False, "boundary", requested=requested, completed=completed, results=results, boundary=b, detail=detail, revision=revision, control=control), 30


def run(driver: str, request: dict[str, Any], timeout: float, worldline_path: Path, presenter: Path):
    steps = request["steps"]
    requested = len(steps)
    control = resolve_control(request.get("control", {}))
    overrides: list[dict[str, Any]] = []
    presentations: list[dict[str, Any]] = []
    last_exact_target: tuple[int, int] | None = None
    try:
        process = subprocess.Popen([driver, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, encoding="utf-8", errors="replace", bufsize=1)
    except OSError as exc:
        return envelope(False, "driver_unavailable", requested=requested, detail=str(exc), control=control), 50

    results: list[dict[str, Any]] = []
    completed = 0
    last_revision = None
    try:
        send(process, {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": PROTOCOL, "capabilities": {}, "clientInfo": {"name": "gwcu-action-span", "version": "2.3.0"}}})
        initialized = recv_for(process, 1, timeout)
        if "error" in initialized:
            return envelope(False, "mcp_initialize_failed", requested=requested, detail=compact(initialized), control=control), 50
        send(process, {"jsonrpc": "2.0", "method": "notifications/initialized"})
        send(process, {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        try:
            modes = tool_modes(recv_for(process, 2, min(timeout, 5)))
        except Exception:
            modes = {}

        index, transition, request_id = request["start"], 0, 3
        while 0 <= index < requested:
            transition += 1
            if transition > MAX_TRANSITIONS:
                return fail_boundary(control, presentations, requested, completed, results, "transition_limit", index=index, revision=last_revision)
            step, action = steps[index], steps[index]["action"]
            baseline = last_revision
            if "await" in step:
                try:
                    status = worldline_call(worldline_path, {"op": "status"}, 3)
                    baseline = status.get("revision", baseline) if status.get("ok") else baseline
                except Exception as exc:
                    return envelope(False, "worldline_boundary", requested=requested, completed=completed, results=results, boundary={"index": index, "reason": "worldline_unavailable_before_action"}, detail=str(exc), revision=last_revision, control=control), 50

            arguments = dict(action["arguments"])
            supports_delivery = bool(modes.get(action["name"]))
            if supports_delivery and "delivery_mode" not in arguments:
                arguments["delivery_mode"] = control["mode"]
            applied = arguments.get("delivery_mode") if supports_delivery else None
            target = exact_target(arguments) if supports_delivery else None
            if target is not None:
                last_exact_target = target

            presentation = None
            if applied == "foreground":
                if target is None:
                    return fail_boundary(control, presentations, requested, completed, results, "exact_target_required_for_foreground", index=index, name=action["name"], detail="foreground Cua input requires exact integer pid + window_id", revision=last_revision)
                presentation = present_exact(presenter, target, min(timeout, 3))
                presentations.append({"index": index, "target": {"pid": target[0], "window_id": target[1]}, "result": presentation})
                if not presentation.get("ok"):
                    return fail_boundary(control, presentations, requested, completed, results, "presentation_not_proved", index=index, name=action["name"], detail=compact(presentation), revision=last_revision)

            send(process, {"jsonrpc": "2.0", "id": request_id, "method": "tools/call", "params": {"name": action["name"], "arguments": arguments}})
            response = recv_for(process, request_id, timeout)
            request_id += 1
            fallback = False
            if applied == "background" and supports_delivery and background_unavailable(response):
                fallback = True
                if target is None:
                    return fail_boundary(control, presentations, requested, completed, results, "exact_target_required_for_foreground_fallback", index=index, name=action["name"], revision=last_revision)
                presentation = present_exact(presenter, target, min(timeout, 3))
                presentations.append({"index": index, "target": {"pid": target[0], "window_id": target[1]}, "reason": "background_fallback", "result": presentation})
                if not presentation.get("ok"):
                    return fail_boundary(control, presentations, requested, completed, results, "presentation_not_proved_for_fallback", index=index, name=action["name"], detail=compact(presentation), revision=last_revision)
                overrides.append({"index": index, "from": "background", "to": "foreground", "reason": "cua_background_unavailable"})
                arguments["delivery_mode"] = "foreground"
                send(process, {"jsonrpc": "2.0", "id": request_id, "method": "tools/call", "params": {"name": action["name"], "arguments": arguments}})
                response = recv_for(process, request_id, timeout)
                request_id += 1

            result = normalize_result(response)
            failed, reason = boundary(response)
            record = {"index": index, "name": action["name"], "result": result, "control": {"requested": control["mode"], "delivery_mode_supported": supports_delivery, "applied": arguments.get("delivery_mode") if supports_delivery else "driver_default", "fallback": fallback, "presentation": presentation}}
            results.append(record)
            if failed:
                control["runtime_overrides"] = overrides
                return fail_boundary(control, presentations, requested, completed, results, reason or "cua_failure", index=index, name=action["name"], revision=last_revision)
            completed += 1

            wait_result = None
            if "await" in step:
                spec = dict(step["await"])
                spec["op"] = "wait"
                if baseline is not None:
                    spec.setdefault("after_revision", baseline)
                try:
                    wait_result = worldline_call(worldline_path, spec, max(1, min(float(spec.get("timeout_ms", 5000)) / 1000 + 2, 122)))
                except Exception as exc:
                    return envelope(False, "worldline_boundary", requested=requested, completed=completed, results=results, boundary={"index": index, "reason": "worldline_unavailable"}, detail=str(exc), revision=last_revision, control=control), 50
                record["worldline"] = wait_result
                last_revision = wait_result.get("revision", last_revision)
                if not wait_result.get("ok"):
                    return fail_boundary(control, presentations, requested, completed, results, f"worldline_{wait_result.get('code', 'failure')}", index=index, revision=last_revision)
            index = next_index(step, index, wait_result, requested)

        # Visible completion is independent from intermediate delivery mode.
        # Explicit background work may stay background and still present the
        # final exact target here.
        if control.get("visible_required"):
            if last_exact_target is None:
                return fail_boundary(control, presentations, requested, completed, results, "visible_result_has_no_exact_final_target", revision=last_revision)
            final = present_exact(presenter, last_exact_target, min(timeout, 3))
            presentations.append({"index": "final", "target": {"pid": last_exact_target[0], "window_id": last_exact_target[1]}, "result": final})
            if not final.get("ok"):
                return fail_boundary(control, presentations, requested, completed, results, "final_presentation_not_proved", detail=compact(final), revision=last_revision)

        control["runtime_overrides"] = overrides
        control["presentations"] = presentations
        control["runtime_notice"] = "Had to switch to foreground for this." if overrides else None
        return envelope(True, "completed", requested=requested, completed=completed, results=results, revision=last_revision, control=control), 0
    except Exception as exc:
        control["presentations"] = presentations
        return envelope(False, "transport_boundary", requested=requested, completed=completed, results=results, detail=str(exc), revision=last_revision, control=control), 50
    finally:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=1)
            except subprocess.TimeoutExpired:
                process.kill(); process.wait(timeout=1)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--driver")
    parser.add_argument("--worldline-socket")
    parser.add_argument("--presenter")
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
    output, rc = run(driver, request, max(1, min(args.timeout, 120)), worldline_socket(args.worldline_socket), presenter_path(args.presenter))
    print(compact(output))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
