#!/usr/bin/env bash
# uninstall.sh — run the current GWCU teardown, even over older installed copies.
set -euo pipefail
NAME="gnome-wayland-computer-use"
VERSION="2.3.0"
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
REMOVE_CUA=false; PURGE_CUA=false
usage(){ cat <<'HELP'
Usage: uninstall.sh [--keep-cua|--remove-cua|--purge-cua]

Removes GWCU-managed skills/plugins, WORLDLINE + observer user services,
transient runtime state, PATH edits and integration-owned state.
Repo/workspace .gwcu files remain local workspace content.

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

# A checked-out/current script may use its adjacent teardown. Under `curl | bash`,
# BASH_SOURCE is stdin-like: never discover an executable from the caller's CWD.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || self_dir=""
  if [ -n "$self_dir" ] && [ -f "$self_dir/scripts/teardown.sh" ]; then
    TEARDOWN="$self_dir/scripts/teardown.sh"
    [ -f "$self_dir/scripts/migrate-main.sh" ] && MIGRATOR="$self_dir/scripts/migrate-main.sh"
  fi
fi

# Public uninstall intentionally fetches the current cleanup implementation.
# An installed 2.2 bundle contains a stale teardown and must never win merely
# because it exists on disk.
if [ -z "$TEARDOWN" ]; then
  command -v curl >/dev/null || { printf 'error: curl is required\n' >&2; exit 1; }
  TMPDIR=$(mktemp -d); trap 'rm -rf "$TMPDIR"' EXIT
  if curl -fsSL --retry 3 --retry-delay 1 -o "$TMPDIR/teardown.sh" "$BASE_URL/scripts/teardown.sh" &&
     curl -fsSL --retry 3 --retry-delay 1 -o "$TMPDIR/migrate-main.sh" "$BASE_URL/scripts/migrate-main.sh"; then
    TEARDOWN="$TMPDIR/teardown.sh"
    MIGRATOR="$TMPDIR/migrate-main.sh"
  else
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
    [ -n "$TEARDOWN" ] || { printf 'error: could not fetch current teardown and no trusted %s install is available\n' "$VERSION" >&2; exit 1; }
  fi
fi

if [ -n "$MIGRATOR" ]; then
  /bin/bash "$MIGRATOR" --repair --quiet ||
    printf '[WARN] legacy-main repair was incomplete; current teardown will continue\n' >&2
fi

args=(--force); $REMOVE_CUA && args+=(--remove-cua); $PURGE_CUA && args=(--force --purge-cua)
exec /bin/bash "$TEARDOWN" "${args[@]}"
