#!/usr/bin/env python3
"""WORLDLINE shim — delegates to ryanraposo/WORLDLINE package.

Exposes the same command surface as GWCU's embedded worldline.py
(``serve``, ``self-test``, ``request --json``) but backs it with the
WORLDLINE package daemon.  Daemon responses are re-wrapped into GWCU's
``gwcu.worldline.v1`` envelope so existing call sites keep working.

WORLDLINE never injects input. Cua Driver remains the sole control authority.
The shim supports the ``op=="wait"`` operation through delegation to the
WORLDLINE daemon's revisioned wait loop, and the daemon ingests events on
``Thread(target=client`` while a wait is pending, so contingent continuation
works without blocking observation.
"""
from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

_xdg_data = os.environ.get("XDG_DATA_HOME")

# Locate the WORLDLINE package. Candidates in priority order:
#   1. GWCU_WORLDLINE_ROOT/src          (explicit override)
#   2. XDG_DATA_HOME/.../worldline-pkg/src  (installed by GWCU installer)
#   3. ~/repos/WORLDLINE/src            (development fallback)
_candidates = [
    Path(os.environ.get("GWCU_WORLDLINE_ROOT", "")) / "src",
    Path(
        (_xdg_data or str(Path.home() / ".local/share"))
        + "/gnome-wayland-computer-use/worldline-pkg/src"
    ),
    Path.home() / "repos" / "WORLDLINE" / "src",
]
SRC = None
for candidate in _candidates:
    if candidate.is_dir() and (candidate / "worldline").is_dir():
        SRC = candidate
        break

if SRC is not None:
    # Remove any duplicate entries so the WORLDLINE package takes priority
    # over this shim's own directory (named worldline.py, which shadows the
    # package name).
    sys.path = [p for p in sys.path if p != str(SRC)]
    sys.path.insert(0, str(SRC))

if SRC is None:
    raise SystemExit(
        "worldline: ryanraposo/WORLDLINE package not found; "
        "run install.sh or set GWCU_WORLDLINE_ROOT"
    )

from worldline.control import request as wl_request  # noqa: E402


def _default_socket() -> str:
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    return str(Path(runtime) / "worldline" / "worldline.sock")


def _gwcu_payload_to_worldline(raw: str) -> tuple[str, dict]:
    try:
        doc = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"worldline: invalid JSON payload: {exc}")
    if not isinstance(doc, dict):
        raise SystemExit("worldline: payload must be a JSON object")
    op = doc.pop("op", None)
    if not isinstance(op, str) or not op:
        raise SystemExit("worldline: payload missing 'op'")
    args = {k: v for k, v in doc.items() if k not in ("protocol", "request_id")}
    return op, args


def _wrap_gwcu(op: str, daemon_result: dict) -> dict:
    ok = bool(daemon_result.get("ok"))
    result = daemon_result.get("result") or {}

    if not ok:
        error = daemon_result.get("error") or {}
        return {
            "schema": "gwcu.worldline.v1",
            "ok": False,
            "code": error.get("code", "worldline_error"),
            "detail": error.get("message", ""),
        }

    if op == "status":
        return {
            "schema": "gwcu.worldline.v1",
            "ok": True,
            "code": "ok",
            "revision": result.get("revision", 0),
            "facts": result.get("fact_count", 0),
            "state": {"revision": result.get("revision", 0)},
            "socket": _default_socket(),
        }
    if op == "capture":
        return {
            "schema": "gwcu.worldline.revision.v1",
            "ok": True,
            "code": "applied",
            "revision": result.get("revision", 0),
            "previous_revision": result.get("previous_revision", 0),
            "boundary": result.get("boundary", {}),
            "predicates_satisfied": result.get("predicates_satisfied", []),
            "predicates_unsatisfied": result.get("predicates_unsatisfied", []),
            "woken": result.get("woken", []),
            "conflicts": result.get("conflicts", []),
            "visual": result.get("visual", {}),
        }
    if op == "fence":
        return {
            "schema": "gwcu.worldline.v1",
            "ok": True,
            "code": "fenced",
            "revision": result.get("revision", 0),
            "boundary": result.get("boundary", {}),
        }
    if op == "arm":
        return {
            "schema": "gwcu.worldline.v1",
            "ok": True,
            "code": "armed",
            "id": result.get("id", ""),
            "revision": result.get("revision", 0),
        }
    if op == "wait":
        mp = result.get("matched_predicates", result.get("predicates", []))
        predicate_ids = [str(p.get("id", "")) for p in mp if isinstance(p, dict) and p.get("id")]
        code = result.get("code", "ready")
        return {
            "schema": "gwcu.worldline.v1",
            "ok": code in ("ready",),
            "code": code,
            "revision": result.get("revision", 0),
            "after_revision": result.get("after_revision", 0),
            "matched_branch": result.get("matched_branch"),
            "predicates": predicate_ids,
            "conflict_paths": result.get("conflict_paths", []),
        }
    if op == "event":
        return {
            "schema": "gwcu.worldline.v1",
            "ok": True,
            "code": "applied",
            "revision": result.get("revision", 0),
            "woken": result.get("woken", []),
        }
    out = {"schema": "gwcu.worldline.v1", "ok": True, "code": "ok"}
    out.update(result)
    return out


def _cmd_request(raw: str) -> int:
    op, args_dict = _gwcu_payload_to_worldline(raw)
    socket_path = os.environ.get("WORLDLINE_SOCKET") or _default_socket()
    try:
        daemon_result = wl_request(socket_path, op, args_dict)
    except Exception as exc:  # noqa: BLE001
        print(json.dumps({
            "schema": "gwcu.worldline.v1", "ok": False,
            "code": "worldline_unavailable", "detail": str(exc),
        }, separators=(",", ":")))
        return 30
    wrapped = _wrap_gwcu(op, daemon_result)
    print(json.dumps(wrapped, separators=(",", ":")))
    return 0 if wrapped.get("ok") else 30


def _cmd_self_test() -> int:
    """Run a self-contained revision/predicate self-test using a local daemon.

    Mirrors the coverage of GWCU's original embedded self-test: event
    ingestion, predicate waits, branch selection, fresh_after semantics.
    """
    runtime = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sock_path = str(Path(runtime) / "gnome-wayland-computer-use" / "worldline.sock")

    # Start a local daemon on the test socket.
    proc = subprocess.Popen(
        [sys.executable, "-m", "worldline.daemon", "--socket", sock_path],
        stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL, start_new_session=True,
        env=dict(os.environ),
    )
    try:
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            if Path(sock_path).exists():
                try:
                    wl_request(sock_path, "status", {})
                    break
                except Exception:
                    pass
            if proc.poll() is not None:
                break
            time.sleep(0.05)
        else:
            print(json.dumps({
                "schema": "gwcu.worldline.v1", "ok": False,
                "code": "self_test_failed",
                "detail": "daemon socket did not appear",
            }, separators=(",", ":")))
            return 50

        def req(op: str, args: dict) -> dict:
            raw = wl_request(sock_path, op, args)
            return _wrap_gwcu(op, raw)

        passed = []

        # 1. status works
        r = req("status", {})
        assert r.get("ok") and r.get("revision") is not None, r
        passed.append("status")

        # 2. event ingestion + predicate wait
        r = req("event", {"event": {
            "source": "task", "type": "download-complete",
            "facts": {"task.download.done": True},
            "invalidates": ["ui.semantic"],
        }})
        assert r.get("ok") and r.get("code") == "applied", r
        rev_after_event = r.get("revision", 0)

        r = req("wait", {
            "timeout_ms": 2000,
            "predicates": [{"id": "done", "path": "task.download.done",
                            "op": "eq", "value": True}],
        })
        assert r.get("ok") and r.get("code") == "ready", r
        assert "done" in r.get("predicates", []), r
        assert r.get("revision", 0) >= rev_after_event, r
        passed.append("event+wait")

        # 3. branch selection
        r = req("wait", {
            "timeout_ms": 50,
            "branches": [
                {"id": "downloaded", "predicates": [
                    {"path": "task.download.done", "op": "eq", "value": True}]},
                {"id": "dialog", "predicates": [
                    {"path": "ui.dialog.name", "op": "exists"}]},
            ],
        })
        assert r.get("ok") and r.get("matched_branch") == "downloaded", r
        passed.append("branches")

        # 4. fresh_after rejects cached truth
        r = req("event", {"event": {
            "source": "task", "facts": {"task.fresh": True},
        }})
        stale_rev = r.get("revision", 0)

        r = req("wait", {
            "timeout_ms": 40,
            "predicates": [{"path": "task.fresh", "op": "eq", "value": True,
                            "fresh_after": stale_rev}],
        })
        assert not r.get("ok"), r
        assert r.get("code") == "timeout", r

        r = req("event", {"event": {
            "source": "task", "facts": {"task.fresh": True},
        }})
        r = req("wait", {
            "timeout_ms": 100,
            "predicates": [{"path": "task.fresh", "op": "eq", "value": True,
                            "fresh_after": stale_rev}],
        })
        assert r.get("ok") and r.get("code") == "ready", r
        passed.append("fresh_after")

        # 5. close
        r = req("close", {})
        assert r.get("ok"), r
        passed.append("close")

    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait(timeout=2)

    print(json.dumps({
        "schema": "gwcu.worldline.v1", "ok": True, "code": "self_test_ok",
        "checks": passed,
    }, separators=(",", ":")))
    return 0


def _cmd_serve() -> int:
    """Start the WORLDLINE package daemon on the GWCU socket path."""
    sock_path = os.environ.get("WORLDLINE_SOCKET") or _default_socket()
    # Give the package daemon the GWCU socket path.
    env = dict(os.environ)
    env["WORLDLINE_SOCKET"] = sock_path
    # Also ensure the package can import itself.
    env["PYTHONPATH"] = os.pathsep.join(filter(None, [
        str(SRC), env.get("PYTHONPATH", ""),
    ]))
    os.execvpe(sys.executable, [sys.executable, "-m", "worldline.daemon",
                                "--socket", sock_path], env)


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print("usage: worldline.py serve|self-test|request --json '<payload>'",
              file=sys.stderr)
        return 2
    command = args[0]
    if command == "serve":
        return _cmd_serve()
    if command == "self-test":
        return _cmd_self_test()
    if command == "request":
        if len(args) < 3 or args[1] != "--json":
            print("usage: worldline.py request --json '<payload>'",
                  file=sys.stderr)
            return 2
        raw = args[2] if len(args) > 2 else "{}"
        return _cmd_request(raw)
    print(f"unknown command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
