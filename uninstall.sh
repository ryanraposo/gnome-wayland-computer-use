#!/usr/bin/env bash
# uninstall.sh — complete GWCU uninstall, including Cua only when GWCU provisioned it.
set -euo pipefail

NAME=gnome-wayland-computer-use
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
SELF=""
[ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ] && SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEEP_CUA=false
PURGE_CUA=false

usage() {
    cat <<'HELP'
Usage: uninstall.sh [--keep-cua] [--purge-cua]

By default GWCU removes all project-managed files and removes Cua Driver only
when GWCU originally provisioned it. Ubuntu packages and portal permissions are preserved.

  --keep-cua   always preserve Cua Driver
  --purge-cua  deliberately remove Cua Driver even if it predated GWCU, including Cua data
HELP
}

while [ $# -gt 0 ]; do
    case "$1" in
        --keep-cua) KEEP_CUA=true ;;
        --purge-cua) PURGE_CUA=true ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'error: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

TEARDOWN=""
for candidate in \
    "${SELF:+$SELF/scripts/teardown.sh}" \
    "$HOME/.agents/skills/$NAME/scripts/teardown.sh" \
    "${HERMES_HOME:-$HOME/.hermes}/skills/computer-use/scripts/teardown.sh"; do
    [ -n "$candidate" ] && [ -f "$candidate" ] || continue
    TEARDOWN="$candidate"; break
done

TMP=""
if [ -z "$TEARDOWN" ]; then
    command -v curl >/dev/null 2>&1 || { printf 'error: curl is required to fetch teardown.sh\n' >&2; exit 1; }
    TMP=$(mktemp)
    trap 'rm -f "$TMP"' EXIT
    curl -fsSL --retry 3 --retry-delay 1 -o "$TMP" "$BASE_URL/scripts/teardown.sh" || {
        printf 'error: could not download teardown.sh\n' >&2; exit 1;
    }
    TEARDOWN="$TMP"
fi

args=(--force)
if $PURGE_CUA; then args+=(--purge-cua)
elif ! $KEEP_CUA; then args+=(--remove-cua)
fi
exec /bin/bash "$TEARDOWN" "${args[@]}"
