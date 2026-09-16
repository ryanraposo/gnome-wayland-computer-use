#!/usr/bin/env python3
"""Thin stdio MCP client for Cua Driver's stable health_report contract."""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys

from mcp_client import recv_for, resolve_driver, send

SCHEMA = "gwcu.cua-health.v2"
PROTOCOL = "2024-11-05"
_SEMVER = re.compile(r"\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b")


def envelope(ok: bool, code: str, report=None, detail: str | None = None):
    out = {"schema": SCHEMA, "ok": ok, "code": code, "report": report, "next": None}
    if detail:
        out["detail"] = detail
    return out


def reported_version(report) -> str | None:
    if not isinstance(report, dict):
        return None
    for entry in report.get("checks") or []:
        if not isinstance(entry, dict) or entry.get("name") != "binary_version":
            continue
        text = " ".join(str(entry.get(k) or "") for k in ("message", "detail", "summary"))
        if match := _SEMVER.search(text):
            return match.group(1)
    return None


def executable_version(driver: str) -> str | None:
    try:
        proc = subprocess.run(
            [driver, "--version"], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, encoding="utf-8", errors="replace", timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    text = (proc.stdout or "") + "\n" + (proc.stderr or "")
    match = _SEMVER.search(text)
    return match.group(1) if match else None


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
    payload["binary"] = os.path.realpath(driver)
    payload["executable_version"] = executable_version(driver)
    payload["reported_version"] = reported_version(payload.get("report"))
    payload["identity_ok"] = bool(
        payload["executable_version"]
        and payload["reported_version"]
        and payload["executable_version"] == payload["reported_version"]
    )
    if payload.get("ok") and not payload["identity_ok"]:
        payload["ok"] = False
        payload["code"] = "identity_split_brain"
        payload["next"] = {"action": "repair_cua_identity"}
        rc = 40
    print(json.dumps(payload, separators=(",", ":")))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
