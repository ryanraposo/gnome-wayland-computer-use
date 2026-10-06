#!/usr/bin/env bash
# uninstall.sh — run the current GWCU teardown, even over older installed copies.
set -euo pipefail
NAME="gnome-wayland-computer-use"
VERSION="2.4.0"
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
PYTHON="${GWCU_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
REMOVE_CUA=false; PURGE_CUA=false
usage(){ cat <<'HELP'
Usage: uninstall.sh [--keep-cua|--remove-cua|--purge-cua]

Removes GWCU-managed skills/plugins from the default Hermes home and every
existing profile, WORLDLINE + observer user services, transient runtime state,
PATH edits and integration-owned state. Archived pre-GWCU components are
restored when possible. Hermes' built-in `computer_use` tool/toolset is never
removed. Repo/workspace .gwcu files remain local workspace content.

The public uninstaller always uses the current teardown logic, so installations
made by older `main` versions are repaired/removed instead of executing their
stale bundled teardown.

  --keep-cua    preserve Cua Driver (default)
  --remove-cua  remove Cua only when GWCU originally provisioned it
  --purge-cua   explicitly purge Cua even when it predated GWCU
HELP
}
for a in "$@"; do case "$a" in --keep-cua) REMOVE_CUA=false;PURGE_CUA=false;; --remove-cua) REMOVE_CUA=true;; --purge-cua) REMOVE_CUA=true;PURGE_CUA=true;; --help|-h) usage;exit 0;; *) printf 'error: unknown option: %s\n' "$a" >&2;exit 2;; esac; done

TEARDOWN=""
MIGRATOR=""
TMPDIR=""

fetch_verified_release(){
  local metadata archive release_root release_name expected_sha expected_commit expected_size actual_sha actual_size
  [ -n "$PYTHON" ] && [ -x "$PYTHON" ] || { printf 'error: python3 is required to verify the GWCU release\n' >&2; return 20; }
  command -v curl >/dev/null 2>&1 || return 10
  command -v sha256sum >/dev/null 2>&1 || { printf 'error: sha256sum is required to verify the GWCU release\n' >&2; return 20; }
  case "$BASE_URL" in https://*) ;; *) printf 'error: remote GWCU source must use HTTPS: %s\n' "$BASE_URL" >&2; return 20;; esac

  TMPDIR=$(mktemp -d)
  metadata="$TMPDIR/release.json"
  archive="$TMPDIR/release.tar.gz"
  if ! curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 120 -o "$metadata" "$BASE_URL/dist/gwcu-$VERSION.json"; then
    return 10
  fi
  mapfile -t release_info < <("$PYTHON" - "$metadata" "$VERSION" <<'PY'
import json,re,sys
path,version=sys.argv[1:]
try:d=json.load(open(path))
except Exception as exc:raise SystemExit(f"invalid release metadata: {exc}")
if d.get("schema")!="gwcu.release.v1":raise SystemExit("unsupported release metadata schema")
if d.get("version")!=version:raise SystemExit("release version mismatch")
archive=d.get("archive")
if archive!=f"gwcu-{version}.tar.gz":raise SystemExit("unexpected release archive")
sha=str(d.get("sha256") or "");commit=str(d.get("commit") or "");size=d.get("bytes")
if not re.fullmatch(r"[0-9a-f]{64}",sha):raise SystemExit("invalid release sha256")
if not re.fullmatch(r"[0-9a-f]{40}",commit):raise SystemExit("invalid release commit")
if not isinstance(size,int) or size<=0:raise SystemExit("invalid release size")
print(archive);print(sha);print(commit);print(size)
PY
  ) || { printf 'error: GWCU release metadata verification failed\n' >&2; return 20; }
  [ "${#release_info[@]}" -eq 4 ] || { printf 'error: incomplete GWCU release identity\n' >&2; return 20; }
  release_name="${release_info[0]}"; expected_sha="${release_info[1]}"; expected_commit="${release_info[2]}"; expected_size="${release_info[3]}"

  if ! curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 3 --retry-all-errors --connect-timeout 10 --max-time 180 -o "$archive" "$BASE_URL/dist/$release_name"; then
    return 10
  fi
  actual_size=$(wc -c <"$archive" | tr -d '[:space:]')
  [ "$actual_size" = "$expected_size" ] || { printf 'error: GWCU release archive size mismatch\n' >&2; return 20; }
  actual_sha=$(sha256sum "$archive" | awk '{print $1}')
  [ "$actual_sha" = "$expected_sha" ] || { printf 'error: GWCU release archive SHA-256 mismatch\n' >&2; return 20; }

  release_root="$TMPDIR/release"
  mkdir -p "$release_root"
  "$PYTHON" - "$archive" "$release_root" "$VERSION" "$expected_commit" <<'PY' || { printf 'error: GWCU release extraction/identity verification failed\n' >&2; return 20; }
import json,pathlib,sys,tarfile
archive,dest,version,commit=sys.argv[1:]
with tarfile.open(archive,"r:gz") as tf:
    members=tf.getmembers()
    for m in members:
        p=pathlib.PurePosixPath(m.name)
        if p.is_absolute() or ".." in p.parts or m.issym() or m.islnk() or m.isdev():
            raise SystemExit(f"unsafe release member: {m.name}")
    tf.extractall(dest,filter="data")
root=pathlib.Path(dest)
identity=json.load(open(root/".gwcu-release.json"))
assert identity.get("schema")=="gwcu.release.v1"
assert identity.get("version")==version
assert identity.get("commit")==commit
assert (root/"scripts/teardown.sh").is_file()
assert (root/"scripts/migrate-main.sh").is_file()
PY
  TEARDOWN="$release_root/scripts/teardown.sh"
  MIGRATOR="$release_root/scripts/migrate-main.sh"
  printf '[OK] Verified GWCU teardown source %s @ %.12s\n' "$VERSION" "$expected_commit"
  return 0
}

# A checked-out/current script may use its adjacent teardown. Under `curl | bash`,
# BASH_SOURCE is stdin-like: never discover an executable from the caller's CWD.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || self_dir=""
  if [ -n "$self_dir" ] && [ -f "$self_dir/scripts/teardown.sh" ]; then
    TEARDOWN="$self_dir/scripts/teardown.sh"
    [ -f "$self_dir/scripts/migrate-main.sh" ] && MIGRATOR="$self_dir/scripts/migrate-main.sh"
  fi
fi

# Public uninstall consumes the same verified current release as install.
# Network unavailability may fall back to a managed same-generation install;
# integrity/provenance failure never downgrades to local code.
if [ -z "$TEARDOWN" ]; then
  trap '[ -n "$TMPDIR" ] && rm -rf "$TMPDIR"' EXIT
  set +e
  fetch_verified_release
  fetch_rc=$?
  set -e
  if [ "$fetch_rc" -eq 10 ]; then
    # Offline fallback is allowed only for an installed bundle that proves it
    # is this generation. Never execute an arbitrary/stale historical teardown.
    for dir in \
      "$HOME/.agents/skills/$NAME" \
      "${HERMES_HOME:-$HOME/.hermes}/skills/computer-use"
    do
      [ -f "$dir/VERSION" ] && [ -f "$dir/scripts/teardown.sh" ] || continue
      [ "$(tr -d '[:space:]' <"$dir/VERSION")" = "$VERSION" ] || continue
      [ -f "$dir/.gnome-wayland-computer-use-managed" ] || continue
      TEARDOWN="$dir/scripts/teardown.sh"
      [ -f "$dir/scripts/migrate-main.sh" ] && MIGRATOR="$dir/scripts/migrate-main.sh"
      break
    done
    [ -n "$TEARDOWN" ] || { printf 'error: release endpoint unavailable and no trusted %s install is available\n' "$VERSION" >&2; exit 1; }
    printf '[WARN] Release endpoint unavailable; using managed installed teardown %s\n' "$VERSION" >&2
  elif [ "$fetch_rc" -ne 0 ]; then
    printf 'error: refusing uninstall because current release integrity could not be proved\n' >&2
    exit 1
  fi
fi

if [ -n "$MIGRATOR" ]; then
  /bin/bash "$MIGRATOR" --repair --quiet ||
    printf '[WARN] legacy-main repair was incomplete; current teardown will continue\n' >&2
fi

args=(--force); $REMOVE_CUA && args+=(--remove-cua); $PURGE_CUA && args=(--force --purge-cua)
exec /bin/bash "$TEARDOWN" "${args[@]}"
