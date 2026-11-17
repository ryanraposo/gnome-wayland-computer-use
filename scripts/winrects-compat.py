#!/usr/bin/env python3
"""Keep Cua's winrects@cua extension compatible with the running GNOME Shell.

GNOME marks an extension OUT OF DATE when metadata.json's ``shell-version``
list omits the running shell's major version. Cua's helper ships a list that
can lag a newer distro shell (for example 45-49 on GNOME 50), so the extension
never becomes ACTIVE and exact presentation can never be proved.

This repairs that one field in place, keeps a single backup beside the
metadata, and is idempotent. It changes no extension code and touches no other
component.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

UUID = "winrects@cua"
BACKUP_SUFFIX = ".gwcu-backup"


def extension_dir() -> Path:
    data = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local/share")
    return Path(data) / "gnome-shell" / "extensions" / UUID


def running_shell_major() -> str | None:
    try:
        proc = subprocess.run(
            ["gnome-shell", "--version"],
            capture_output=True, text=True, timeout=5, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return None
    match = re.search(r"\b([0-9]+)\.[0-9]+", proc.stdout)
    return match.group(1) if match else None


def _sort_key(value: str):
    return (0, int(value), "") if value.isdigit() else (1, 0, value)


def ensure(path: Path, major: str) -> str:
    """Add *major* to shell-version once. Returns a stable status token."""
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError, UnicodeDecodeError):
        return "unreadable"
    if not isinstance(data, dict):
        return "unreadable"

    values = data.get("shell-version")
    if not isinstance(values, list):
        values = []
    values = [str(v).strip() for v in values if str(v).strip()]
    major = str(int(major))
    if major in values:
        return "current"

    backup = path.with_name(path.name + BACKUP_SUFFIX)
    if not backup.exists():
        try:
            shutil.copy2(path, backup)
        except OSError:
            return "backup_failed"

    values.append(major)
    data["shell-version"] = sorted(set(values), key=_sort_key)
    try:
        path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    except OSError:
        return "write_failed"
    return "patched"


def main(argv: list[str]) -> int:
    major = argv[1] if len(argv) > 1 else running_shell_major()
    if not major or not str(major).isdigit():
        print("no-shell-version")
        return 0
    path = extension_dir() / "metadata.json"
    if not path.is_file():
        print("not-installed")
        return 0
    status = ensure(path, major)
    print(status)
    return 0 if status in {"current", "patched"} else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
