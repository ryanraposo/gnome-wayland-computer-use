#!/usr/bin/env python3
"""Shared stdio MCP client helpers for Cua Driver.

One transport contract for cua-health.py, portal-control.py and
action-span.py so the JSON-RPC plumbing is not copied three times.
"""
from __future__ import annotations

import json
import os
import pathlib
import selectors
import shutil
import time


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


def send(proc, payload: dict) -> None:
    assert proc.stdin is not None
    proc.stdin.write(compact(payload) + "\n")
    proc.stdin.flush()


def recv_for(proc, request_id: int, timeout: float) -> dict:
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
