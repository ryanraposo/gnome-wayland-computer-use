#!/usr/bin/env bash
# uninstall.sh — find the installed GWCU teardown and reverse GWCU integration.
set -euo pipefail
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
REMOVE_CUA=false; PURGE_CUA=false
usage(){ cat <<'HELP'
Usage: uninstall.sh [--keep-cua|--remove-cua|--purge-cua]

Removes GWCU-managed skills/plugins, WORLDLINE + observer user services,
transient runtime state, PATH edits and integration-owned state.
Repo/workspace .gwcu files remain local workspace content.

  --keep-cua    preserve Cua Driver (default)
  --remove-cua  remove Cua only when GWCU originally provisioned it
  --purge-cua   explicitly purge Cua even when it predated GWCU
HELP
}
for a in "$@"; do case "$a" in --keep-cua) REMOVE_CUA=false;PURGE_CUA=false;; --remove-cua) REMOVE_CUA=true;; --purge-cua) REMOVE_CUA=true;PURGE_CUA=true;; --help|-h) usage;exit 0;; *) printf 'error: unknown option: %s\n' "$a" >&2;exit 2;; esac; done

candidates=()
# Under `curl | bash`, BASH_SOURCE[0] is empty/stdin-like. Never derive an
# adjacent executable path from the caller's current directory in that case.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  self_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd) || self_dir=""
  [ -n "$self_dir" ] && candidates+=("$self_dir/scripts/teardown.sh")
fi
candidates+=(
  "$HOME/.agents/skills/gnome-wayland-computer-use/scripts/teardown.sh"
  "${HERMES_HOME:-$HOME/.hermes}/skills/computer-use/scripts/teardown.sh"
)
TEARDOWN=""; for f in "${candidates[@]}"; do [ -f "$f" ] && { TEARDOWN="$f";break; }; done
TMP=""; if [ -z "$TEARDOWN" ]; then command -v curl >/dev/null || { printf 'error: curl is required\n' >&2;exit 1; }; TMP=$(mktemp);trap 'rm -f "$TMP"' EXIT;curl -fsSL --retry 3 --retry-delay 1 -o "$TMP" "$BASE_URL/scripts/teardown.sh" || { printf 'error: could not fetch teardown.sh\n' >&2;exit 1; };TEARDOWN="$TMP";fi
args=(--force);$REMOVE_CUA && args+=(--remove-cua);$PURGE_CUA && args=(--force --purge-cua)
exec /bin/bash "$TEARDOWN" "${args[@]}"
