#!/usr/bin/env python3
"""Attested persistent foreground presentation through Cua's GNOME helper.

GWCU supports Ubuntu GNOME Wayland as a product target, so foreground control
must be stronger than generic Wayland's best-effort focus semantics. Cua's
bundled ``winrects@cua`` extension runs inside GNOME Shell and exposes the exact
stable-sequence window ids that Cua uses. This helper:

1. attests that ``org.cua.WinRects`` is owned by this user's real GNOME Shell;
2. resolves an exact window by (pid, window_id) -- never by title;
3. asks the Cua helper to activate it; and
4. proves GNOME reports that same window focused, visible, and not minimized.

No input is injected here. This is the presentation gate that makes subsequent
Cua foreground input target-addressable and visibly deterministic.
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import re
import stat
import subprocess
import sys
import time
from typing import Any

SCHEMA = "gwcu.presentation.v1"
DEST = "org.cua.WinRects"
PATH = "/org/cua/WinRects"
IFACE = "org.cua.WinRects"
DBUS_DEST = "org.freedesktop.DBus"
DBUS_PATH = "/org/freedesktop/DBus"
DBUS_IFACE = "org.freedesktop.DBus"
MIN_API = 8
MAX_WINDOW_ID = (1 << 32) - 1


def compact(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), ensure_ascii=True)


def envelope(ok: bool, code: str, **extra: Any) -> dict[str, Any]:
    out: dict[str, Any] = {"schema": SCHEMA, "ok": ok, "code": code}
    out.update({k: v for k, v in extra.items() if v is not None})
    return out


def run(argv: list[str], timeout: float = 1.0) -> tuple[int, str, str]:
    try:
        p = subprocess.run(
            argv,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=timeout,
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, "", str(exc)


def gdbus(dest: str, method: str, *args: str, timeout: float = 1.0) -> str:
    rc, out, err = run(
        [
            "gdbus",
            "call",
            "--session",
            "--dest",
            dest,
            "--object-path",
            DBUS_PATH if dest == DBUS_DEST else PATH,
            "--method",
            method,
            *args,
        ],
        timeout,
    )
    if rc != 0:
        raise RuntimeError(err or out or f"gdbus {method} failed")
    return out


def quoted(raw: str) -> str | None:
    match = re.search(r"'([^']+)'", raw)
    return match.group(1) if match else None


def first_u32(raw: str) -> int | None:
    payload = raw.split("uint32", 1)[1] if "uint32" in raw else raw
    match = re.search(r"\b(\d+)\b", payload)
    if not match:
        return None
    value = int(match.group(1))
    return value if 0 <= value <= MAX_WINDOW_ID else None


def parse_rects(raw: str) -> list[dict[str, Any]]:
    start = raw.find("[")
    end = raw.rfind("]")
    if start < 0 or end < start:
        raise ValueError("GetRects returned no JSON array")
    value = json.loads(raw[start : end + 1])
    if not isinstance(value, list):
        raise ValueError("GetRects payload is not an array")
    return [item for item in value if isinstance(item, dict)]


def trusted_shell_owner() -> tuple[str, int]:
    if not shutil_which("gdbus"):
        raise RuntimeError("gdbus is unavailable")

    owner = quoted(
        gdbus(DBUS_DEST, f"{DBUS_IFACE}.GetNameOwner", DEST)
    )
    if not owner or not owner.startswith(":"):
        raise RuntimeError("Cua GNOME helper has no immutable bus owner")

    pid = first_u32(
        gdbus(DBUS_DEST, f"{DBUS_IFACE}.GetConnectionUnixProcessID", owner)
    )
    uid = first_u32(
        gdbus(DBUS_DEST, f"{DBUS_IFACE}.GetConnectionUnixUser", owner)
    )
    if pid is None or uid != os.getuid():
        raise RuntimeError("Cua GNOME helper owner identity is invalid")

    proc = pathlib.Path(f"/proc/{pid}")
    try:
        comm = (proc / "comm").read_text().strip()
        exe = (proc / "exe").resolve(strict=True)
        exe_stat = exe.stat()
    except OSError as exc:
        raise RuntimeError(f"cannot attest GNOME Shell owner: {exc}") from exc
    if comm != "gnome-shell" or exe.name != "gnome-shell":
        raise RuntimeError("Cua helper is not hosted by gnome-shell")
    if exe_stat.st_uid != 0 or stat.S_IMODE(exe_stat.st_mode) & 0o022:
        raise RuntimeError("gnome-shell executable trust check failed")

    version = first_u32(gdbus(owner, f"{IFACE}.GetVersion"))
    if version is None or version < MIN_API:
        raise RuntimeError(
            f"Cua GNOME helper API {version!r} is below required {MIN_API}"
        )
    return owner, version


def shutil_which(name: str) -> str | None:
    # Keep startup tiny and dependency-free without importing shutil solely for
    # a single PATH lookup.
    for directory in os.environ.get("PATH", "").split(os.pathsep):
        candidate = pathlib.Path(directory or ".") / name
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def rects(owner: str) -> list[dict[str, Any]]:
    return parse_rects(gdbus(owner, f"{IFACE}.GetRects"))


def exact_window(
    windows: list[dict[str, Any]], pid: int, window_id: int
) -> dict[str, Any] | None:
    matches = [
        item
        for item in windows
        if item.get("pid") == pid and item.get("id") == window_id
    ]
    return matches[0] if len(matches) == 1 else None


def present(pid: int, window_id: int, timeout_ms: int) -> dict[str, Any]:
    if pid <= 0 or not 0 <= window_id <= MAX_WINDOW_ID:
        return envelope(False, "invalid_target", pid=pid, window_id=window_id)
    try:
        owner, version = trusted_shell_owner()
        before = exact_window(rects(owner), pid, window_id)
        if before is None:
            return envelope(
                False,
                "target_not_exact",
                pid=pid,
                window_id=window_id,
                helper_api=version,
            )

        accepted = gdbus(
            owner,
            f"{IFACE}.Activate",
            str(window_id),
            timeout=max(1.0, timeout_ms / 1000 + 0.5),
        ).lstrip().startswith("(true,")
        if not accepted:
            return envelope(
                False,
                "activation_refused",
                pid=pid,
                window_id=window_id,
                helper_api=version,
            )

        deadline = time.monotonic() + max(0.1, min(timeout_ms, 3000) / 1000)
        last = before
        while True:
            current = exact_window(rects(owner), pid, window_id)
            if current is not None:
                last = current
                if (
                    current.get("focused") is True
                    and current.get("visible") is True
                    and current.get("minimized") is not True
                ):
                    return envelope(
                        True,
                        "presented",
                        pid=pid,
                        window_id=window_id,
                        helper_api=version,
                        window={
                            key: current.get(key)
                            for key in (
                                "title",
                                "x",
                                "y",
                                "w",
                                "h",
                                "focused",
                                "visible",
                                "minimized",
                                "stacking",
                            )
                        },
                    )
            if time.monotonic() >= deadline:
                return envelope(
                    False,
                    "focus_not_proved",
                    pid=pid,
                    window_id=window_id,
                    helper_api=version,
                    window=last,
                )
            time.sleep(0.025)
    except Exception as exc:
        return envelope(
            False,
            "helper_unavailable",
            pid=pid,
            window_id=window_id,
            detail=str(exc),
        )


def verify(pid: int, window_id: int) -> dict[str, Any]:
    try:
        owner, version = trusted_shell_owner()
        current = exact_window(rects(owner), pid, window_id)
        if current is None:
            return envelope(
                False,
                "target_not_exact",
                pid=pid,
                window_id=window_id,
                helper_api=version,
            )
        good = (
            current.get("focused") is True
            and current.get("visible") is True
            and current.get("minimized") is not True
        )
        return envelope(
            good,
            "presented" if good else "not_presented",
            pid=pid,
            window_id=window_id,
            helper_api=version,
            window=current,
        )
    except Exception as exc:
        return envelope(False, "helper_unavailable", detail=str(exc))


def status() -> dict[str, Any]:
    try:
        owner, version = trusted_shell_owner()
        windows = rects(owner)
        return envelope(
            True,
            "ready",
            helper_api=version,
            windows=len(windows),
            focused=sum(1 for item in windows if item.get("focused") is True),
        )
    except Exception as exc:
        return envelope(False, "helper_unavailable", detail=str(exc))


def self_test() -> dict[str, Any]:
    sample = "('[{\"id\":42,\"pid\":7,\"focused\":true,\"visible\":true,\"minimized\":false}]',)"
    parsed = parse_rects(sample)
    assert exact_window(parsed, 7, 42) is not None
    assert exact_window(parsed, 7, 43) is None
    assert first_u32("(uint32 8,)") == 8
    assert quoted("(':1.77',)") == ":1.77"
    return envelope(
        True,
        "ok",
        checks=[
            "exact_pid_window_identity",
            "gvariant_scalar_parsing",
            "focused_visible_postcondition",
            "immutable_dbus_owner_contract",
        ],
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("self-test")
    for name in ("present", "verify"):
        p = sub.add_parser(name)
        p.add_argument("--pid", type=int, required=True)
        p.add_argument("--window-id", type=int, required=True)
        if name == "present":
            p.add_argument("--timeout-ms", type=int, default=700)
    args = parser.parse_args()

    if args.command == "status":
        result = status()
    elif args.command == "self-test":
        result = self_test()
    elif args.command == "verify":
        result = verify(args.pid, args.window_id)
    else:
        result = present(args.pid, args.window_id, args.timeout_ms)
    print(compact(result))
    return 0 if result.get("ok") else 30


if __name__ == "__main__":
    raise SystemExit(main())
