#!/usr/bin/env python3
"""Client of the standalone WORLDLINE socket; GWCU owns no revision daemon."""
from __future__ import annotations

import argparse
import json
import os
import socket
import sys
from pathlib import Path
from typing import Any

PROTOCOL = 1
MAX_RESPONSE = 1 << 20


def socket_path() -> Path:
    return Path(os.getenv("WORLDLINE_SOCKET") or
                Path(os.getenv("XDG_RUNTIME_DIR", f"/tmp/worldline-{os.getuid()}"))
                / "worldline" / "worldline.sock")


def call(payload: dict[str, Any], *, path: Path | None = None,
         timeout: float = 5.0) -> dict[str, Any]:
    request = {
        "protocol": PROTOCOL, "op": payload["op"],
        "args": {key: value for key, value in payload.items()
                 if key not in ("op", "protocol", "request_id")},
        "request_id": payload.get("request_id", "gwcu"),
    }
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as client:
        client.settimeout(timeout)
        client.connect(str(path or socket_path()))
        client.sendall((json.dumps(request, separators=(",", ":")) + "\n").encode())
        data = bytearray()
        while b"\n" not in data and len(data) <= MAX_RESPONSE:
            chunk = client.recv(65536)
            if not chunk:
                break
            data.extend(chunk)
    if not data or len(data) > MAX_RESPONSE:
        raise RuntimeError("WORLDLINE returned no bounded response")
    response = json.loads(bytes(data).split(b"\n", 1)[0])
    if response.get("protocol") != PROTOCOL:
        raise RuntimeError("WORLDLINE protocol mismatch")
    if not response.get("ok"):
        return {"ok": False, "code": response.get("error", {}).get("code", "failure"),
                "detail": response.get("error", {}).get("message")}
    result = response["result"]
    if not isinstance(result, dict):
        return {"ok": True, "result": result}
    code = result.get("code", "ok")
    return {"ok": code not in ("timeout", "conflict", "pending"), **result}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["request", "self-test"])
    parser.add_argument("--json")
    args = parser.parse_args()
    if args.command == "self-test":
        try:
            result = call({"op": "hello"}, timeout=1)
            good = result.get("protocol") == PROTOCOL and result.get("revision_domain") == "worldline"
        except (OSError, ValueError, RuntimeError):
            good = False
        print(json.dumps({"ok": good, "code": "ready" if good else "worldline_unavailable"}))
        return 0 if good else 1
    try:
        raw = json.loads(args.json) if args.json else json.load(sys.stdin)
        result = call(raw, timeout=max(5, min(float(raw.get("timeout_ms", 0)) / 1000 + 2, 122)))
    except (OSError, ValueError, KeyError, RuntimeError) as exc:
        result = {"ok": False, "code": "worldline_unavailable", "detail": str(exc)}
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result.get("ok") else 30


if __name__ == "__main__":
    raise SystemExit(main())
