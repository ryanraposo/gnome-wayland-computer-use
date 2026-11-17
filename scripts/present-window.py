#!/usr/bin/env python3
"""Read-only exact-target admission through WORLDLINE.

GWCU never activates a window. WORLDLINE supplies compositor observations;
CUA remains the sole actuator. This gate admits focus-sensitive input only
when the requested (pid, window_id) is uniquely bound and already focused.
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

SCHEMA = "gwcu.presentation.v2"
MAX_WINDOW_ID = (1 << 64) - 1
MAX_OBSERVATION_AGE = 2.5


def envelope(ok: bool, code: str, **extra: Any) -> dict[str, Any]:
    return {"schema": SCHEMA, "ok": ok, "code": code, **extra}


def worldline_query() -> dict[str, Any]:
    client = Path(__file__).resolve().with_name("worldline.py")
    payload = json.dumps({"op": "query", "paths": ["windows"], "fresh": True},
                         separators=(",", ":"))
    try:
        proc = subprocess.run(
            [sys.executable, str(client), "request", "--json", payload],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, encoding="utf-8",
            errors="replace", timeout=7,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise RuntimeError(f"WORLDLINE query failed: {exc}") from exc
    try:
        result = json.loads(proc.stdout.strip()) if proc.stdout.strip() else {}
    except json.JSONDecodeError as exc:
        raise RuntimeError("WORLDLINE returned invalid JSON") from exc
    if proc.returncode != 0 or result.get("ok") is not True:
        raise RuntimeError(str(result.get("detail") or result.get("code") or proc.stderr[:512]))
    values = result.get("values")
    windows = values.get("windows") if isinstance(values, dict) else None
    fact = (result.get("facts") or {}).get("windows")
    evidence = fact.get("evidence") if isinstance(fact, dict) else None
    if not isinstance(windows, dict) or not isinstance(evidence, dict):
        raise RuntimeError("WORLDLINE did not return a versioned windows observation")
    observed_at = evidence.get("observed_at")
    expires_at = evidence.get("expires_at")
    if (not isinstance(observed_at, (int, float))
            or not isinstance(expires_at, (int, float))
            or time.time() - observed_at > MAX_OBSERVATION_AGE
            or expires_at < time.time()):
        raise RuntimeError("WORLDLINE window observation is stale")
    return {"windows": windows, "revision": result.get("revision"),
            "observed_at": observed_at, "expires_at": expires_at,
            "source": evidence.get("source")}


def exact_window(windows: dict[str, Any], pid: int, window_id: int) -> dict[str, Any] | None:
    items = windows.get("items")
    if not isinstance(items, list):
        return None
    matches = [
        item for item in items
        if isinstance(item, dict)
        and item.get("pid") == pid
        and item.get("cua_window_id") == window_id
        and item.get("compositor_verified") is True
        and item.get("geometry_source") == "worldline-gnome-shell"
    ]
    return matches[0] if len(matches) == 1 else None


def geometry(window: dict[str, Any]) -> dict[str, Any] | None:
    frame = window.get("frame")
    if not isinstance(frame, dict):
        return None
    keys = ("x", "y", "width", "height")
    values = [frame.get(key) for key in keys]
    if any(type(value) is not int for value in values):
        return None
    if values[2] <= 0 or values[3] <= 0:
        return None
    return {key: frame[key] for key in keys}


def presented(window: dict[str, Any] | None) -> bool:
    return bool(
        window is not None
        and window.get("focused") is True
        and window.get("visible") is True
        and window.get("minimized") is False
        and geometry(window) is not None
    )


def inspect(pid: int, window_id: int) -> dict[str, Any]:
    if pid <= 0 or not 0 <= window_id <= MAX_WINDOW_ID:
        return envelope(False, "invalid_target", pid=pid, window_id=window_id)
    try:
        snapshot = worldline_query()
    except Exception as exc:
        return envelope(False, "worldline_unavailable", detail=str(exc),
                        pid=pid, window_id=window_id)
    windows = snapshot["windows"]
    window = exact_window(windows, pid, window_id)
    if window is None:
        return envelope(False, "target_not_exact",
                        detail="WORLDLINE did not bind this CUA window_id to exactly one compositor-verified window",
                        pid=pid, window_id=window_id, revision=snapshot["revision"])
    if not presented(window):
        return envelope(False, "target_not_verified_foreground",
                        detail="GWCU does not activate windows; focus, visibility and stable geometry must already be observed",
                        pid=pid, window_id=window_id, revision=snapshot["revision"],
                        observed={"focused": window.get("focused"),
                                  "visible": window.get("visible"),
                                  "minimized": window.get("minimized"),
                                  "geometry": geometry(window)})
    return envelope(True, "verified_foreground", mode="verified_foreground",
                    pid=pid, window_id=window_id, revision=snapshot["revision"],
                    observed_at=snapshot["observed_at"],
                    source=snapshot["source"],
                    window={"stable_id": window.get("stable_id"),
                            "cua_window_id": window.get("cua_window_id"),
                            "compositor_id": window.get("compositor_id"),
                            "title": window.get("title"),
                            "frame": geometry(window),
                            "monitor": (window.get("geometry") or {}).get("monitor"),
                            "scale": (window.get("geometry") or {}).get("scale"),
                            "focused": True, "visible": True, "minimized": False})


def capability_state(available: bool, reason: Any = None) -> str:
    if available:
        return "available"
    detail = str(reason or "").casefold()
    if "permission" in detail or "denied" in detail or "not authorized" in detail:
        return "denied"
    if "stale" in detail:
        return "stale"
    return "unavailable"


def status() -> dict[str, Any]:
    try:
        snapshot = worldline_query()
    except Exception as exc:
        state = "stale" if "stale" in str(exc).casefold() else "unavailable"
        return envelope(False, "worldline_unavailable", detail=str(exc),
                        capabilities={"window_observation": state,
                                      "exact_target_binding": state,
                                      "activation": "unsupported"})
    windows = snapshot["windows"]
    items = windows.get("items") if isinstance(windows.get("items"), list) else []
    exact = [item for item in items if isinstance(item, dict)
             and item.get("compositor_verified") is True
             and item.get("geometry_source") == "worldline-gnome-shell"]
    sources = windows.get("sources") if isinstance(windows.get("sources"), dict) else {}
    semantic = (sources.get("semantic") or {}).get("available") is True
    geometry_source = sources.get("geometry") or {}
    compositor = geometry_source.get("available") is True and geometry_source.get("name") == "worldline-gnome-shell"
    return envelope(
        True, "capabilities_reported",
        revision=snapshot["revision"],
        observed_at=snapshot["observed_at"],
        mode="verified_foreground" if compositor else ("semantic_interaction" if semantic else "observe_only"),
        capabilities={
            "window_observation": capability_state(windows.get("available") is True, windows.get("reason")),
            "exact_target_binding": capability_state(compositor, geometry_source.get("reason")),
            "compositor_geometry": capability_state(compositor, geometry_source.get("reason")),
            "semantic_inspection": capability_state(semantic, (sources.get("semantic") or {}).get("reason")),
            "activation": "unsupported",
            "desktop_capture": "unknown",
            "remote_desktop_input": "unknown",
            "portal_authorization": "unknown",
        },
        execution_modes={
            "full_foreground": "unsupported",
            "verified_foreground": "available" if compositor else "unavailable",
            "semantic_interaction": "available" if semantic else "unavailable",
            "desktop_visual_interaction": "unknown",
            "observe_only": "available",
        },
        windows={"count": windows.get("count", len(items)),
                 "verified": len(exact),
                 "semantic_only": (windows.get("counts") or {}).get("semantic_only", 0),
                 "geometry_only": (windows.get("counts") or {}).get("geometry_only", 0)},
        focus=windows.get("focus"),
        sources=sources,
    )


def self_test() -> dict[str, Any]:
    sample = {"items": [{
        "pid": 42, "cua_window_id": 0x12345678, "compositor_id": 7, "compositor_verified": True,
        "geometry_source": "worldline-gnome-shell",
        "frame": {"x": -20, "y": 0, "width": 800, "height": 600},
        "focused": True, "visible": True, "minimized": False,
    }]}
    row = exact_window(sample, 42, 0x12345678)
    assert row is not None and presented(row)
    assert exact_window(sample, 42, 7) is None
    assert exact_window(sample, 99, 0x12345678) is None
    assert geometry({**row, "frame": {"x": 0, "y": 0, "width": 0, "height": 10}}) is None
    assert not presented({**row, "focused": False})
    assert not presented({**row, "visible": False})
    assert not presented({**row, "minimized": True})
    # Semantic-only or inferred frames can never satisfy exact-target binding.
    assert exact_window(sample, 42, 0x12345678) is row
    unverified = {**sample, "items": [{**row, "compositor_verified": False}]}
    assert exact_window(unverified, 42, 0x12345678) is None
    return envelope(True, "ok", checks=[
        "worldline_exact_pid_cua_window_id_binding",
        "focus_visibility_minimized_gate",
        "fresh_compositor_geometry_required",
        "no_activation_or_input_surface",
        "semantic_only_cannot_admit_coordinate_input",
    ])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("status")
    sub.add_parser("self-test")
    for name in ("present", "verify"):
        p = sub.add_parser(name)
        p.add_argument("--pid", type=int, required=True)
        p.add_argument("--window-id", type=int, required=True)
        p.add_argument("--timeout-ms", type=int, default=700,
                       help="bounded caller budget; observation remains read-only")
    args = parser.parse_args()
    if args.command == "status":
        result = status()
    elif args.command == "self-test":
        result = self_test()
    else:
        result = inspect(args.pid, args.window_id)
    print(json.dumps(result, separators=(",", ":"), ensure_ascii=False))
    return 0 if result.get("ok") else 30


if __name__ == "__main__":
    raise SystemExit(main())
