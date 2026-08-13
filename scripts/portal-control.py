#!/usr/bin/env python3
"""Inspect or establish Cua's GNOME RemoteDesktop -> EIS/libei input session."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import selectors
import shutil
import subprocess
import sys
import time

SCHEMA = "gwcu.portal-control.v1"
PROTOCOL = "2024-11-05"


def compact(value) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=False)


def resolve_driver(explicit: str | None) -> str | None:
    if explicit:
        return explicit
    env = os.environ.get("CUA_DRIVER_BIN")
    if env:
        return env
    found = shutil.which("cua-driver")
    if found:
        return found
    candidate = pathlib.Path.home() / ".local/bin/cua-driver"
    return str(candidate) if candidate.is_file() and os.access(candidate, os.X_OK) else None


def token_path() -> pathlib.Path:
    override = os.environ.get("GWCU_LIBEI_TOKEN")
    if override:
        return pathlib.Path(override)
    config = pathlib.Path(os.environ.get("XDG_CONFIG_HOME", pathlib.Path.home() / ".config"))
    return config / "cua-driver" / "libei-persistent.token"


def portal_available() -> bool:
    forced = os.environ.get("GWCU_REMOTE_DESKTOP_AVAILABLE")
    if forced is not None:
        return forced.strip().casefold() not in {"", "0", "false", "off", "no"}
    gdbus = shutil.which("gdbus")
    if not gdbus:
        return False
    try:
        proc = subprocess.run(
            [
                gdbus, "introspect", "--session",
                "--dest", "org.freedesktop.portal.Desktop",
                "--object-path", "/org/freedesktop/portal/desktop",
            ],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return proc.returncode == 0 and "interface org.freedesktop.portal.RemoteDesktop" in proc.stdout


def integration_checks() -> dict:
    unit = pathlib.Path.home() / ".config/systemd/user/gnome-wayland-computer-use.service"
    ydotool = pathlib.Path.home() / ".config/systemd/user/ydotoold.service"
    udev = pathlib.Path("/etc/udev/rules.d/80-gnome-wayland-computer-use.rules")
    return {
        "gwcu_rdp_or_vnc_server": False,
        "gwcu_control_service_present": unit.exists(),
        "gwcu_ydotoold_present": ydotool.exists(),
        "gwcu_input_udev_rule_present": udev.exists(),
        "gwcu_raw_input_path": unit.exists() or ydotool.exists() or udev.exists(),
    }


def base_status(driver: str | None) -> dict:
    token = token_path()
    portal = portal_available()
    return {
        "schema": SCHEMA,
        "ok": bool(driver) and portal,
        "code": "authorized" if driver and portal and token.is_file() else ("ready_for_consent" if driver and portal else "unavailable"),
        "portal": {
            "interface": "org.freedesktop.portal.RemoteDesktop",
            "available": portal,
            "purpose": "local pointer and keyboard delivery",
            "devices": ["pointer", "keyboard"],
            "transport": ["D-Bus", "EIS", "libei"],
            "restore_token": {"path": str(token), "present": token.is_file()},
        },
        "cua": {"driver": driver, "present": bool(driver)},
        "integration": integration_checks(),
        "next": None if token.is_file() else {"action": "authorize_remote_desktop"},
    }


def send(proc: subprocess.Popen[str], payload: dict) -> None:
    assert proc.stdin is not None
    proc.stdin.write(compact(payload) + "\n")
    proc.stdin.flush()


def recv_for(proc: subprocess.Popen[str], request_id: int, timeout: float) -> dict:
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


def tool_result(response: dict, name: str) -> dict:
    if "error" in response:
        raise RuntimeError(f"{name}: {compact(response['error'])}")
    result = response.get("result") or {}
    if result.get("isError") is True:
        content = result.get("content")
        raise RuntimeError(f"{name}: {compact(content if content is not None else result)}")
    return result


def structured(result: dict) -> dict:
    value = result.get("structuredContent") or result.get("structured_content")
    return value if isinstance(value, dict) else {}


def authorize(driver: str, timeout: float) -> tuple[dict, int]:
    status = base_status(driver)
    if not status["portal"]["available"]:
        status.update(ok=False, code="portal_missing", next={"action": "restore_remote_desktop_portal"})
        return status, 50

    try:
        proc = subprocess.Popen(
            [driver, "mcp"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            bufsize=1,
        )
    except OSError as exc:
        status.update(ok=False, code="driver_unavailable", detail=str(exc))
        return status, 50

    try:
        send(proc, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL,
                "capabilities": {},
                "clientInfo": {"name": "gnome-wayland-computer-use", "version": "2.3.0"},
            },
        })
        init = recv_for(proc, 1, min(timeout, 10.0))
        if "error" in init or not isinstance(init.get("result"), dict):
            raise RuntimeError(f"initialize: {compact(init)}")
        send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})

        width = height = None
        send(proc, {
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "get_screen_size", "arguments": {}},
        })
        try:
            size = structured(tool_result(recv_for(proc, 2, min(timeout, 10.0)), "get_screen_size"))
            width = int(size.get("width")) if size.get("width") is not None else None
            height = int(size.get("height")) if size.get("height") is not None else None
        except (RuntimeError, ValueError, TypeError):
            width = height = None

        # Pointer motion is the least invasive public Cua input operation that
        # establishes the portal session: no click and no key are emitted.
        x = max(1, width // 2) if width and width > 1 else 1
        y = max(1, height // 2) if height and height > 1 else 1
        send(proc, {
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": {"name": "move_cursor", "arguments": {"scope": "desktop", "x": x, "y": y}},
        })
        move = tool_result(recv_for(proc, 3, timeout), "move_cursor")
        status = base_status(driver)
        status.update(
            ok=True,
            code="authorized",
            handshake={"operation": "move_cursor", "scope": "desktop", "x": x, "y": y, "click": False, "key": False},
            cua_result=structured(move) or None,
            next=None,
        )
        return status, 0
    except (TimeoutError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        status = base_status(driver)
        status.update(
            ok=False,
            code="authorization_failed",
            detail=str(exc),
            next={"action": "approve_remote_desktop_and_retry"},
        )
        return status, 30
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
    group = parser.add_mutually_exclusive_group()
    group.add_argument("--status", action="store_true", help="report the local portal-control contract")
    group.add_argument("--authorize", action="store_true", help="establish the RemoteDesktop/EIS session with pointer-only motion")
    parser.add_argument("--driver", help="cua-driver executable")
    parser.add_argument("--timeout", type=float, default=45.0)
    args = parser.parse_args()

    driver = resolve_driver(args.driver)
    if args.authorize:
        if not driver:
            payload = base_status(None)
            payload.update(ok=False, code="driver_missing")
            print(compact(payload))
            return 50
        payload, rc = authorize(driver, max(5.0, min(args.timeout, 120.0)))
    else:
        payload = base_status(driver)
        rc = 0 if payload["ok"] else 30
    print(compact(payload))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
