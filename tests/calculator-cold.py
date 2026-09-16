#!/usr/bin/env python3
"""Live GWCU/Cua regression: closed → launch → bind → present → cursor → 137×42 → 5754.

Headless CI intentionally skips this test. Run it from the real GNOME Wayland
session with GWCU_LIVE_CALCULATOR=1 after installation.
"""
from __future__ import annotations

import json
import os
import pathlib
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))
from mcp_client import recv_for, resolve_driver, send  # noqa: E402

SESSION = "gwcu-calculator-cold"
PROTOCOL = "2024-11-05"


def skip(reason: str) -> int:
    print(f"ok - cold Calculator live regression skipped: {reason}")
    return 0


def structured(result: dict):
    if result.get("isError") is True:
        raise AssertionError(f"Cua tool failed: {json.dumps(result, separators=(',', ':'))}")
    value = result.get("structuredContent") or result.get("structured_content")
    if value is not None:
        return value
    for block in result.get("content") or []:
        if isinstance(block, dict) and block.get("type") == "text":
            try:
                return json.loads(block.get("text") or "")
            except json.JSONDecodeError:
                pass
    return result


def windows(value) -> list[dict]:
    if isinstance(value, list):
        return [row for row in value if isinstance(row, dict)]
    if isinstance(value, dict):
        for key in ("windows", "items", "result"):
            if isinstance(value.get(key), list):
                return [row for row in value[key] if isinstance(row, dict)]
    return []


def key(row: dict):
    pid, wid = row.get("pid"), row.get("window_id")
    return (pid, wid) if isinstance(pid, int) and pid > 0 and isinstance(wid, int) else None


def is_calculator(row: dict) -> bool:
    hay = " ".join(str(row.get(k) or "") for k in ("app_name", "name", "title", "window_title", "bundle_id")).casefold()
    return "calculator" in hay or "gnome-calculator" in hay


def main() -> int:
    if os.environ.get("GWCU_LIVE_CALCULATOR") != "1":
        return skip("set GWCU_LIVE_CALCULATOR=1 to opt into visible desktop control")
    if os.environ.get("XDG_SESSION_TYPE", "").casefold() != "wayland":
        raise SystemExit("not ok - cold Calculator requires the live Wayland session")

    driver = resolve_driver(None)
    if not driver:
        raise SystemExit("not ok - cua-driver is unavailable")
    presenter = ROOT / "scripts" / "present-window.py"
    resolver = ROOT / "scripts" / "app-identity.sh"

    resolved = subprocess.run(
        [str(resolver), "--resolve", "--machine", "Calculator"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5, check=False,
    )
    if resolved.returncode:
        raise SystemExit(f"not ok - Calculator did not resolve locally: {resolved.stdout or resolved.stderr}")
    identity = json.loads(resolved.stdout)["result"]

    proc = subprocess.Popen(
        [driver, "mcp"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
    )
    next_id = 1

    def rpc(method: str, params: dict | None = None, timeout: float = 8.0):
        nonlocal next_id
        rid = next_id
        next_id += 1
        send(proc, {"jsonrpc": "2.0", "id": rid, "method": method, "params": params or {}})
        msg = recv_for(proc, rid, timeout)
        if "error" in msg:
            raise AssertionError(f"MCP {method} failed: {msg['error']}")
        return msg.get("result") or {}

    def tool(name: str, args: dict | None = None, timeout: float = 8.0):
        return structured(rpc("tools/call", {"name": name, "arguments": args or {}}, timeout))

    try:
        rpc("initialize", {
            "protocolVersion": PROTOCOL, "capabilities": {},
            "clientInfo": {"name": "gwcu-calculator-cold", "version": "1"},
        })
        send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        # Establish a genuinely cold start using Cua itself, never a shell kill.
        existing = [row for row in windows(tool("list_windows")) if is_calculator(row)]
        for row in existing:
            if isinstance(row.get("pid"), int) and row["pid"] > 0:
                tool("kill_app", {"pid": row["pid"]})
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline:
            if not any(is_calculator(row) for row in windows(tool("list_windows"))):
                break
            time.sleep(0.05)
        else:
            raise AssertionError("Calculator was not closed before ACQUIRE")

        before_rows = windows(tool("list_windows"))
        before = {k for row in before_rows if (k := key(row)) is not None}

        # ACQUIRE: local resolution already proved above; Cua owns launch.
        launched = tool("launch_app", {"name": identity["display_name"]})
        launched_pid = launched.get("pid") if isinstance(launched, dict) else None
        deadline = time.monotonic() + 8.0
        bound = None
        candidates: list[dict] = []
        while time.monotonic() < deadline:
            current = windows(tool("list_windows"))
            candidates = [row for row in current if (k := key(row)) is not None and k not in before and is_calculator(row)]
            if isinstance(launched_pid, int) and launched_pid > 0:
                same_pid = [row for row in candidates if row.get("pid") == launched_pid]
                if same_pid:
                    candidates = same_pid
            if len(candidates) == 1:
                bound = candidates[0]
                break
            if len(candidates) > 1:
                raise AssertionError(f"ACQUIRE produced ambiguous new Calculator windows: {candidates}")
            time.sleep(0.05)
        if bound is None:
            raise AssertionError(f"ACQUIRE never produced one exact new Calculator window; launch={launched!r}")

        pid, window_id = key(bound)
        assert pid and window_id is not None

        # PRESENT: GWCU proves the exact native target is focused + visible.
        presented = subprocess.run(
            [sys.executable, str(presenter), "present", "--pid", str(pid), "--window-id", str(window_id)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=8, check=False,
        )
        presentation = json.loads(presented.stdout or "{}")
        assert presented.returncode == 0 and presentation.get("ok"), presentation or presented.stderr

        target = {"kind": "window", "pid": pid, "window_id": window_id}

        # VISIBLE CURSOR: move the compositor-owned Cua agent cursor, then read
        # its independent semantic state rather than inferring visibility.
        tool("move_cursor", {"target": target, "x": 64, "y": 64, "session": SESSION})
        cursor = tool("get_agent_cursor_state", {"session": SESSION})
        assert isinstance(cursor, dict) and cursor.get("visible") is True, cursor

        # ACT + VERIFY: exact same native target all the way through.
        tool("type_text", {
            "target": target, "pid": pid, "window_id": window_id,
            "text": "137*42", "delivery_mode": "foreground", "session": SESSION,
        })
        tool("press_key", {
            "target": target, "pid": pid, "window_id": window_id,
            "key": "return", "delivery_mode": "foreground", "session": SESSION,
        })
        state = tool("get_window_state", {
            "pid": pid, "window_id": window_id, "query": "5754",
            "include_screenshot": False, "session": SESSION,
        }, 12.0)
        if "5754" not in json.dumps(state, ensure_ascii=False):
            raise AssertionError(f"Calculator did not expose verified result 5754: {state!r}")

        print(f"ok - cold Calculator: closed -> acquired ({pid},{window_id}) -> presented -> cursor visible -> 5754")
        return 0
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=1)


if __name__ == "__main__":
    raise SystemExit(main())
