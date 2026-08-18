"""Hermes command integration for gnome-wayland-computer-use."""
from __future__ import annotations

import os
from pathlib import Path
import shlex
import subprocess


NAME = "gnome-wayland-computer-use"
ARGS_HINT = "[status|background [on|off|status]|managed [on|off|status]|truths|consent|doctor|help]"


def _backend() -> Path:
    hermes_home = Path(os.environ.get("HERMES_HOME", Path.home() / ".hermes"))
    candidates = [
        hermes_home / "skills" / "computer-use" / "scripts" / "computer-use.sh",
        Path.home() / ".agents" / "skills" / NAME / "scripts" / "computer-use.sh",
    ]
    for path in candidates:
        if path.is_file():
            return path
    return candidates[-1]


def _run(raw_args: str) -> str:
    backend = _backend()
    if not backend.is_file():
        return f"computer-use backend is missing: {backend}"
    try:
        argv = shlex.split(raw_args or "")
    except ValueError as exc:
        return f"Invalid /computer-use arguments: {exc}"
    try:
        proc = subprocess.run(
            [str(backend), *argv],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=90,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"/computer-use failed: {exc}"
    text = (proc.stdout or "").strip()
    err = (proc.stderr or "").strip()
    if proc.returncode and err:
        text = f"{text}\n{err}".strip()
    return text or f"/computer-use exited {proc.returncode}"


def register(ctx):
    ctx.register_command(
        "computer-use",
        _run,
        description="Ubuntu desktop control priority, .gwcu truths, consent, and diagnostics.",
        args_hint=ARGS_HINT,
    )
