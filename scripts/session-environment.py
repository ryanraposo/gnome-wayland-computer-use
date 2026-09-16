#!/usr/bin/env python3
"""Synchronize and prove the GNOME Wayland environment across shell/systemd/Hermes gateways."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import stat
import subprocess
import sys

SCHEMA = "gwcu.session-environment.v1"
KEYS = (
    "DISPLAY",
    "WAYLAND_DISPLAY",
    "XDG_SESSION_TYPE",
    "XDG_CURRENT_DESKTOP",
    "XDG_RUNTIME_DIR",
)
_GATEWAY_MARKERS = (
    "hermes gateway run",
    "gateway.run",
    "gateway/run.py",
    "hermes-gateway",
)


def run(argv: list[str], *, env=None, timeout=8) -> tuple[int, str, str]:
    try:
        p = subprocess.run(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            timeout=timeout,
        )
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except (OSError, subprocess.TimeoutExpired) as exc:
        return 127, "", str(exc)


def subset(env: dict[str, str] | os._Environ[str]) -> dict[str, str | None]:
    return {key: env.get(key) for key in KEYS}


def validate_live(values: dict[str, str | None]) -> tuple[bool, list[str], str | None]:
    failures: list[str] = []
    wayland = values.get("WAYLAND_DISPLAY") or ""
    runtime = values.get("XDG_RUNTIME_DIR") or ""
    session = values.get("XDG_SESSION_TYPE") or ""
    desktop = values.get("XDG_CURRENT_DESKTOP") or ""

    if not wayland:
        failures.append("WAYLAND_DISPLAY is missing")
    elif wayland.startswith(":"):
        failures.append(f"WAYLAND_DISPLAY is not a Wayland socket name: {wayland!r}")
    if session.casefold() != "wayland":
        failures.append(f"XDG_SESSION_TYPE is not wayland: {session!r}")
    if "gnome" not in desktop.casefold():
        failures.append(f"XDG_CURRENT_DESKTOP is not GNOME: {desktop!r}")
    if not runtime:
        failures.append("XDG_RUNTIME_DIR is missing")

    socket_path: pathlib.Path | None = None
    if wayland and runtime and not wayland.startswith(":"):
        socket_path = pathlib.Path(wayland) if os.path.isabs(wayland) else pathlib.Path(runtime) / wayland
        try:
            mode = socket_path.stat().st_mode
            if not stat.S_ISSOCK(mode):
                failures.append(f"WAYLAND_DISPLAY is not a live socket: {socket_path}")
        except OSError:
            failures.append(f"WAYLAND_DISPLAY socket is not live: {socket_path}")

    return not failures, failures, str(socket_path) if socket_path else None


def systemd_environment() -> tuple[dict[str, str | None], str | None]:
    rc, out, err = run(["systemctl", "--user", "show-environment"])
    if rc != 0:
        return {key: None for key in KEYS}, err or f"systemctl exited {rc}"
    env: dict[str, str] = {}
    for line in out.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        env[key] = value
    return subset(env), None


def proc_environment(pid: int) -> dict[str, str]:
    raw = pathlib.Path(f"/proc/{pid}/environ").read_bytes()
    env: dict[str, str] = {}
    for field in raw.split(b"\0"):
        if b"=" not in field:
            continue
        key, value = field.split(b"=", 1)
        env[key.decode(errors="replace")] = value.decode(errors="replace")
    return env


def running_gateway_pids() -> list[int]:
    """Discover this user's live Hermes gateway processes without trusting status text."""
    found: list[int] = []
    uid = os.getuid()
    for proc in pathlib.Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            if proc.stat().st_uid != uid:
                continue
            cmdline = proc.joinpath("cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").casefold()
        except OSError:
            continue
        if any(marker in cmdline for marker in _GATEWAY_MARKERS):
            found.append(int(proc.name))
    return sorted(set(found))


def _attestation_map() -> dict[int, dict]:
    state = pathlib.Path(os.getenv("XDG_STATE_HOME", str(pathlib.Path.home() / ".local/state"))) / "gnome-wayland-computer-use"
    rows: dict[int, dict] = {}
    for path in sorted(state.glob("hermes-gateway-identity-*.json")):
        try:
            attested = json.loads(path.read_text())
            pid = int(attested.get("pid") or 0)
            if pid <= 0:
                continue
            attested["_path"] = str(path)
            rows[pid] = attested
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            continue
    return rows


def gateway_attestations() -> list[dict]:
    attestations = _attestation_map()
    pids = set(running_gateway_pids())
    # An attested process is also a gateway authority when still alive, even if
    # a packaging wrapper makes its cmdline unfamiliar to this GWCU release.
    for pid in attestations:
        if pathlib.Path(f"/proc/{pid}").exists():
            pids.add(pid)

    rows: list[dict] = []
    for pid in sorted(pids):
        try:
            live = proc_environment(pid)
        except OSError:
            continue
        attested = attestations.get(pid) or {}
        attested_env = attested.get("environment") if isinstance(attested.get("environment"), dict) else {}
        live_subset = subset(live)
        has_attestation = bool(attested)
        env_match = has_attestation and all(live_subset.get(key) == attested_env.get(key) for key in KEYS)
        selected = attested.get("hermes_selected") if isinstance(attested.get("hermes_selected"), dict) else None
        backend = attested.get("gateway_backend") if isinstance(attested.get("gateway_backend"), dict) else None
        rows.append({
            "pid": pid,
            "hermes_home": live.get("HERMES_HOME") or attested.get("hermes_home"),
            "environment": live_subset,
            "attested_environment": {key: attested_env.get(key) for key in KEYS},
            "environment_attestation_ok": env_match,
            "attested": has_attestation,
            "hermes_cua_driver_cmd": live.get("HERMES_CUA_DRIVER_CMD"),
            "hermes_selected": selected,
            "gateway_backend": backend,
            "attestation": attested.get("_path"),
        })
    return rows


def comparison(shell: dict[str, str | None], systemd: dict[str, str | None], gateways: list[dict]) -> dict:
    systemd_match = all(systemd.get(key) == shell.get(key) for key in KEYS)
    gateway_rows = []
    for gateway in gateways:
        values = gateway.get("environment") or {}
        gateway_rows.append({
            "pid": gateway.get("pid"),
            "matches_shell": all(values.get(key) == shell.get(key) for key in KEYS),
            "attestation_ok": bool(gateway.get("environment_attestation_ok")),
        })
    gateways_match = all(row["matches_shell"] and row["attestation_ok"] for row in gateway_rows)
    return {
        "systemd_matches_shell": systemd_match,
        "gateways_match_shell": gateways_match,
        "gateway_rows": gateway_rows,
    }


def snapshot() -> tuple[dict, int]:
    shell = subset(os.environ)
    shell_ok, shell_failures, socket_path = validate_live(shell)
    systemd, systemd_error = systemd_environment()
    gateways = gateway_attestations()
    compare = comparison(shell, systemd, gateways)
    ok = shell_ok and systemd_error is None and compare["systemd_matches_shell"] and compare["gateways_match_shell"]
    payload = {
        "schema": SCHEMA,
        "ok": ok,
        "code": "ready" if ok else "environment_unproved",
        "shell": {"values": shell, "valid": shell_ok, "failures": shell_failures, "wayland_socket": socket_path},
        "systemd": {"values": systemd, "error": systemd_error},
        "gateways": gateways,
        "comparison": compare,
    }
    return payload, 0 if ok else 30


def sync() -> tuple[dict, int]:
    shell = subset(os.environ)
    valid, failures, socket_path = validate_live(shell)
    if not valid:
        return {
            "schema": SCHEMA,
            "ok": False,
            "code": "invalid_live_wayland_environment",
            "shell": {"values": shell, "failures": failures, "wayland_socket": socket_path},
        }, 30

    env = os.environ.copy()
    # Import by variable name from this validated process environment. Do not
    # synthesize WAYLAND_DISPLAY or substitute an X11-style ':0' value.
    rc1, out1, err1 = run(["systemctl", "--user", "import-environment", *KEYS], env=env)
    rc2, out2, err2 = run(["dbus-update-activation-environment", "--systemd", *KEYS], env=env)
    current, current_error = systemd_environment()
    matches = current_error is None and all(current.get(key) == shell.get(key) for key in KEYS)
    ok = rc1 == 0 and rc2 == 0 and matches
    return {
        "schema": SCHEMA,
        "ok": ok,
        "code": "synchronized" if ok else "synchronization_failed",
        "shell": {"values": shell, "wayland_socket": socket_path},
        "systemd": {"values": current, "error": current_error},
        "commands": {
            "systemctl_import": {"exit": rc1, "stdout": out1, "stderr": err1},
            "dbus_activation_import": {"exit": rc2, "stdout": out2, "stderr": err2},
        },
        "matches": matches,
    }, 0 if ok else 30


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("sync", "snapshot"), nargs="?", default="snapshot")
    args = parser.parse_args()
    payload, rc = sync() if args.action == "sync" else snapshot()
    print(json.dumps(payload, separators=(",", ":"), ensure_ascii=False))
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
