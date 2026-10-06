#!/usr/bin/env bash
# Build one checksum-addressed GWCU release archive from one exact Git commit.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/dist}"
PYTHON="${GWCU_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3)"
command -v git >/dev/null 2>&1 || { printf 'git is required\n' >&2; exit 2; }
command -v tar >/dev/null 2>&1 || { printf 'tar is required\n' >&2; exit 2; }
command -v gzip >/dev/null 2>&1 || { printf 'gzip is required\n' >&2; exit 2; }
command -v sha256sum >/dev/null 2>&1 || { printf 'sha256sum is required\n' >&2; exit 2; }

version="$(tr -d '[:space:]' <"$ROOT/VERSION")"
[ -n "$version" ] || { printf 'VERSION is empty\n' >&2; exit 2; }
commit="$(git -C "$ROOT" rev-parse --verify HEAD)"
epoch="$(git -C "$ROOT" show -s --format=%ct "$commit")"
mkdir -p "$OUT"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

git -C "$ROOT" archive --format=tar "$commit" | tar -xf - -C "$stage"
"$PYTHON" - "$stage/.gwcu-release.json" "$version" "$commit" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    "schema":"gwcu.release.v1",
    "version":sys.argv[2],
    "commit":sys.argv[3],
},separators=(",",":"))+"\n")
PY

archive_name="gwcu-$version.tar.gz"
archive="$OUT/$archive_name"
tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner -C "$stage" -cf - . | gzip -n >"$archive"
digest="$(sha256sum "$archive" | awk '{print $1}')"
size="$(wc -c <"$archive" | tr -d '[:space:]')"
"$PYTHON" - "$OUT/gwcu-$version.json" "$version" "$commit" "$archive_name" "$digest" "$size" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1])
path.write_text(json.dumps({
    "schema":"gwcu.release.v1",
    "version":sys.argv[2],
    "commit":sys.argv[3],
    "archive":sys.argv[4],
    "sha256":sys.argv[5],
    "bytes":int(sys.argv[6]),
},separators=(",",":"))+"\n")
PY

printf 'release=%s\ncommit=%s\nsha256=%s\narchive=%s\n' "$version" "$commit" "$digest" "$archive"
