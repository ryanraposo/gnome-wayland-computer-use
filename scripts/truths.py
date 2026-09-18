#!/usr/bin/env python3
"""Repo/workspace-local .gwcu truth store.

The file is canonical JSON despite its extension: one predictable, human-readable
local state surface with explicit truth classes. Live Cua state always outranks
stored truth.
"""
from __future__ import annotations

import argparse
import itertools
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
from typing import Any

SCHEMA = "gwcu.truths.v1"
MAX_APPS = 64
GENERATED_SECTIONS = ("observed", "capabilities", "calibration", "apps")
ALL_SECTIONS = (*GENERATED_SECTIONS[:-1], "preferences")
_TMP_COUNTER = itertools.count()


def compact(value: Any) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True, ensure_ascii=True)


def tmp_path(path: Path) -> Path:
    """Process- and thread-unique temp path so concurrent writers never collide."""
    return path.with_name(f".{path.name}.{os.getpid()}.{next(_TMP_COUNTER)}.tmp")


def emit(ok: bool, code: str, *, rc: int = 0, **extra: Any) -> int:
    payload = {"schema": SCHEMA, "ok": ok, "code": code, **extra}
    print(compact(payload))
    return rc


def run_git(cwd: Path, *args: str) -> tuple[int, str]:
    try:
        proc = subprocess.run(
            ["git", "-C", str(cwd), *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=4,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return 127, ""
    return proc.returncode, proc.stdout.strip()


def workdir() -> Path:
    raw = os.environ.get("GWCU_WORKDIR") or os.getcwd()
    return Path(raw).expanduser().resolve()


def nearest_existing(start: Path) -> Path | None:
    cur = start if start.is_dir() else start.parent
    for parent in (cur, *cur.parents):
        candidate = parent / ".gwcu"
        if candidate.is_file() and not candidate.is_symlink():
            return parent
    return None


def git_root(start: Path) -> Path | None:
    rc, raw = run_git(start, "rev-parse", "--show-toplevel")
    if rc != 0 or not raw:
        return None
    try:
        return Path(raw).resolve()
    except OSError:
        return None


def resolve_scope() -> tuple[Path, bool, str]:
    explicit = os.environ.get("GWCU_SCOPE_ROOT")
    if explicit:
        root = Path(explicit).expanduser().resolve()
        discovered = git_root(root)
        return root, discovered == root, "environment"

    start = workdir()

    # A Git worktree is always its own truth scope, even when it lives beneath a
    # broader non-Git workspace that already has a .gwcu. This preserves the
    # repo-scoped contract and prevents parent machine/workspace truth from
    # bleeding into a repository.
    repo = git_root(start)
    if repo is not None:
        return repo, True, "git_root"

    # Outside Git, an existing ancestor .gwcu defines a durable workspace scope.
    existing = nearest_existing(start)
    if existing is not None:
        return existing, False, "nearest_truth"

    return start, False, "workdir"


def truth_path(root: Path) -> Path:
    override = os.environ.get("GWCU_FILE")
    return Path(override).expanduser().resolve() if override else root / ".gwcu"


def skeleton() -> dict[str, Any]:
    return {
        "schema": SCHEMA,
        "observed": {},
        "capabilities": {},
        "calibration": {},
        "preferences": {},
        "apps": {},
    }


def load(path: Path) -> dict[str, Any]:
    if not path.exists():
        return skeleton()
    if path.is_symlink():
        raise ValueError("symlink_refused")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ValueError(f"invalid_file:{exc}") from exc
    if not isinstance(value, dict) or value.get("schema") != SCHEMA:
        raise ValueError("unsupported_schema")
    for section in ("observed", "capabilities", "calibration", "preferences", "apps"):
        value.setdefault(section, {})
        if not isinstance(value[section], dict):
            raise ValueError(f"invalid_section:{section}")
    return value


def atomic_write(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.is_symlink():
        raise ValueError("symlink_refused")
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    tmp = tmp_path(path)
    if tmp.exists() or tmp.is_symlink():
        tmp.unlink()
    try:
        text = json.dumps(data, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
        tmp.write_text(text, encoding="utf-8")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    finally:
        if tmp.exists():
            try:
                tmp.unlink()
            except OSError:
                pass


def ensure_gitignore(root: Path) -> tuple[bool, str]:
    path = root / ".gitignore"
    if path.is_symlink():
        return False, "gitignore_symlink_refused"
    try:
        text = path.read_text(encoding="utf-8") if path.exists() else ""
    except OSError:
        return False, "gitignore_read_failed"
    lines = text.splitlines()
    if "/.gwcu" in lines or ".gwcu" in lines:
        return True, "already_ignored"
    block = "# GWCU local machine/workspace truths\n/.gwcu\n"
    new = text
    if new and not new.endswith("\n"):
        new += "\n"
    if new and not new.endswith("\n\n"):
        new += "\n"
    new += block
    try:
        mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o644
        tmp = tmp_path(path)
        if tmp.exists() or tmp.is_symlink():
            tmp.unlink()
        tmp.write_text(new, encoding="utf-8")
        os.chmod(tmp, mode)
        os.replace(tmp, path)
    except OSError:
        return False, "gitignore_write_failed"
    return True, "ignored"


def ensure(root: Path, is_git: bool) -> tuple[Path, str, bool]:
    path = truth_path(root)
    if is_git:
        ok, ignore_code = ensure_gitignore(root)
        if not ok:
            raise ValueError(ignore_code)
    else:
        ignore_code = "not_git"
    created = not path.exists()
    data = load(path)
    if created:
        atomic_write(path, data)
    return path, ignore_code, created


def norm(value: Any) -> str:
    return re.sub(r"[^a-z0-9]+", "-", str(value or "").casefold()).strip("-")


def app_matches(entry: dict[str, Any], query: str) -> bool:
    q = query.casefold()
    qn = norm(query)
    values = (
        entry.get("name"),
        entry.get("desktop_id"),
        entry.get("app_id"),
        entry.get("startup_wm_class"),
        entry.get("key"),
    )
    for value in values:
        if not value:
            continue
        raw = str(value).casefold()
        stem = raw[:-8] if raw.endswith(".desktop") else raw
        if q == raw or q == stem or (qn and qn in {norm(raw), norm(stem)}):
            return True
    return False


def base_scope() -> tuple[Path, bool, str, Path]:
    root, is_git, source = resolve_scope()
    return root, is_git, source, truth_path(root)


def command_scope(_: argparse.Namespace) -> int:
    root, is_git, source, path = base_scope()
    return emit(True, "scope", root=str(root), path=str(path), git=is_git, source=source, exists=path.is_file())


def command_init(_: argparse.Namespace) -> int:
    root, is_git, source, _ = base_scope()
    try:
        path, ignore_code, created = ensure(root, is_git)
    except ValueError as exc:
        return emit(False, str(exc), rc=10, root=str(root), git=is_git, source=source)
    return emit(True, "created" if created else "ready", root=str(root), path=str(path), git=is_git,
                source=source, gitignore=ignore_code, changed=created)


def command_status(_: argparse.Namespace) -> int:
    root, is_git, source, path = base_scope()
    if not path.exists():
        return emit(False, "missing", rc=10, root=str(root), path=str(path), git=is_git, source=source)
    try:
        data = load(path)
    except ValueError as exc:
        return emit(False, str(exc), rc=10, root=str(root), path=str(path), git=is_git, source=source)
    return emit(True, "ready", root=str(root), path=str(path), git=is_git, source=source,
                counts={"apps": len(data["apps"]), "observed": len(data["observed"]),
                        "capabilities": len(data["capabilities"]), "calibration": len(data["calibration"]),
                        "preferences": len(data["preferences"])})


def command_lookup(args: argparse.Namespace) -> int:
    root, is_git, source, path = base_scope()
    if not path.exists():
        return emit(False, "miss", rc=10, root=str(root), path=str(path), git=is_git, source=source, changed=False)
    try:
        data = load(path)
    except ValueError as exc:
        return emit(False, str(exc), rc=10, root=str(root), path=str(path), git=is_git, source=source, changed=False)
    hits = [entry for entry in data["apps"].values() if isinstance(entry, dict) and app_matches(entry, args.target)]
    if len(hits) == 1:
        return emit(True, "hit", root=str(root), path=str(path), git=is_git, source=source, changed=False, identity=hits[0])
    if len(hits) > 1:
        return emit(False, "ambiguous", rc=10, root=str(root), path=str(path), git=is_git, source=source,
                    changed=False, candidates=hits[:8])
    return emit(False, "miss", rc=10, root=str(root), path=str(path), git=is_git, source=source, changed=False)


def command_remember(args: argparse.Namespace) -> int:
    root, is_git, source, _ = base_scope()
    try:
        path, ignore_code, created = ensure(root, is_git)
        data = load(path)
        identity = json.loads(args.identity_json)
    except (ValueError, json.JSONDecodeError) as exc:
        return emit(False, str(exc), rc=10, root=str(root), git=is_git, source=source, changed=False)
    if not isinstance(identity, dict):
        return emit(False, "invalid_identity", rc=10, root=str(root), path=str(path), changed=False)
    key = identity.get("desktop_id") or identity.get("app_id") or norm(identity.get("display_name") or args.target)
    if not key:
        return emit(False, "insufficient_identity", rc=10, root=str(root), path=str(path), changed=False)
    entry = {
        "key": key,
        "name": identity.get("display_name") or args.target,
        "desktop_id": identity.get("desktop_id"),
        "app_id": identity.get("app_id"),
        "startup_wm_class": identity.get("startup_wm_class"),
        "kind": identity.get("kind"),
        "source": "launcher",
    }
    entry = {k: v for k, v in entry.items() if v not in (None, "")}
    old = data["apps"].get(key)
    if old == entry:
        return emit(True, "unchanged", root=str(root), path=str(path), git=is_git, source=source,
                    gitignore=ignore_code, changed=created, identity=entry)
    if old is None and len(data["apps"]) >= MAX_APPS:
        return emit(False, "full", rc=10, root=str(root), path=str(path), limit=MAX_APPS, changed=False)
    data["apps"][key] = entry
    try:
        atomic_write(path, data)
    except ValueError as exc:
        return emit(False, str(exc), rc=10, root=str(root), path=str(path), changed=False)
    return emit(True, "recorded", root=str(root), path=str(path), git=is_git, source=source,
                gitignore=ignore_code, changed=True, identity=entry)


def command_merge(args: argparse.Namespace) -> int:
    if args.section not in ALL_SECTIONS:
        return emit(False, "invalid_section", rc=2, section=args.section)
    root, is_git, source, _ = base_scope()
    try:
        path, ignore_code, created = ensure(root, is_git)
        data = load(path)
        incoming = json.loads(args.json)
    except (ValueError, json.JSONDecodeError) as exc:
        return emit(False, str(exc), rc=10, root=str(root), git=is_git, source=source, changed=False)
    if not isinstance(incoming, dict):
        return emit(False, "merge_requires_object", rc=2, section=args.section)
    before = dict(data[args.section])
    data[args.section].update(incoming)
    changed = created or before != data[args.section]
    if changed:
        try:
            atomic_write(path, data)
        except ValueError as exc:
            return emit(False, str(exc), rc=10, root=str(root), path=str(path), changed=False)
    return emit(True, "merged" if changed else "unchanged", root=str(root), path=str(path), git=is_git,
                source=source, gitignore=ignore_code, changed=changed, section=args.section)


def command_regenerate(_: argparse.Namespace) -> int:
    root, is_git, source, path = base_scope()
    if not path.exists():
        return emit(False, "missing", rc=10, root=str(root), path=str(path), git=is_git, source=source)
    try:
        data = load(path)
    except ValueError as exc:
        return emit(False, str(exc), rc=10, root=str(root), path=str(path), git=is_git, source=source)
    for section in GENERATED_SECTIONS:
        data[section] = {}
    atomic_write(path, data)
    return emit(True, "generated_truths_cleared", root=str(root), path=str(path), git=is_git, source=source,
                preserved=["preferences", "unknown_top_level_keys"], changed=True)


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Read and update the repo/workspace-local .gwcu truth file")
    sub = p.add_subparsers(dest="command", required=True)
    sub.add_parser("scope").set_defaults(func=command_scope)
    sub.add_parser("init").set_defaults(func=command_init)
    sub.add_parser("status").set_defaults(func=command_status)
    lookup = sub.add_parser("lookup"); lookup.add_argument("--target", required=True); lookup.set_defaults(func=command_lookup)
    remember = sub.add_parser("remember"); remember.add_argument("--target", required=True); remember.add_argument("--identity-json", required=True); remember.set_defaults(func=command_remember)
    merge = sub.add_parser("merge"); merge.add_argument("--section", required=True); merge.add_argument("--json", required=True); merge.set_defaults(func=command_merge)
    sub.add_parser("regenerate").set_defaults(func=command_regenerate)
    return p


def main() -> int:
    args = parser().parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
