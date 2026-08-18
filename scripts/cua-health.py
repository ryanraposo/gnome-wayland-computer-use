#!/usr/bin/env python3
"""Thin stdio MCP client for Cua Driver's stable health_report contract."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys

from mcp_client import recv_for, resolve_driver, send

SCHEMA = "gwcu.cua-health.v1"
PROTOCOL = "2024-11-05"


def envelope(ok: bool, code: str, report=None, detail: str | None = None):
    out = {"schema": SCHEMA, "ok": ok, "code": code, "report": report, "next": None}
    if detail:
        out["detail"] = detail
    return out


def run(driver: str, timeout: float) -> tuple[dict, int]:
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
        return envelope(False, "unavailable", detail=str(exc)), 50

    try:
        send(proc, {
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": PROTOCOL,
                "capabilities": {},
                "clientInfo": {"name": "gnome-wayland-computer-use", "version": "2.3.0"},
            },
        })
        init = recv_for(proc, 1, timeout)
        if "error" in init or not isinstance(init.get("result"), dict):
            return envelope(False, "mcp_initialize_failed", detail=json.dumps(init, separators=(",", ":"))), 50

        send(proc, {"jsonrpc": "2.0", "method": "notifications/initialized"})
        send(proc, {
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": {"name": "health_report", "arguments": {}},
        })
        response = recv_for(proc, 2, timeout)
        if "error" in response:
            return envelope(False, "health_report_unavailable", detail=json.dumps(response["error"], separators=(",", ":"))), 50
        result = response.get("result") or {}
        if result.get("isError") is True:
            return envelope(False, "health_report_unavailable", detail=json.dumps(result, separators=(",", ":"))), 50
        report = result.get("structuredContent") or result.get("structured_content")
        if not isinstance(report, dict):
            return envelope(False, "health_report_missing_structured", detail="Cua returned no structuredContent"), 50
        if report.get("schema_version") != "1":
            return envelope(False, "health_schema_unsupported", report=report, detail="Expected Cua health_report schema_version=1"), 50
        overall = report.get("overall")
        if overall == "ok":
            return envelope(True, "ok", report=report), 0
        if overall == "degraded":
            return envelope(False, "degraded", report=report), 30
        if overall == "failed":
            return envelope(False, "failed", report=report), 40
        return envelope(False, "health_report_invalid", report=report, detail=f"Unknown overall={overall!r}"), 50
    except (TimeoutError, RuntimeError, ValueError, json.JSONDecodeError) as exc:
        return envelope(False, "mcp_transport_failed", detail=str(exc)), 50
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
    parser.add_argument("--timeout", type=float, default=8.0)
    args = parser.parse_args()
    driver = resolve_driver(args.driver)
    if not driver:
        print(json.dumps(envelope(False, "driver_missing"), separators=(",", ":")))
        return 50
    payload, rc = run(driver, max(1.0, min(args.timeout, 30.0)))
    print(json.dumps(payload, separators=(",", ":")))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
