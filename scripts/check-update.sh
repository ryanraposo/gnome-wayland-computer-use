#!/usr/bin/env bash
set -euo pipefail

NAME="gnome-wayland-computer-use"
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
STATE_HOME="${GWCU_UPDATE_STATE_HOME:-${GNOME_WAYLAND_COMPUTER_USE_UPDATE_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/$NAME/update}}"
CACHE_SECONDS="${GWCU_UPDATE_CACHE_SECONDS:-${GNOME_WAYLAND_COMPUTER_USE_UPDATE_CACHE_SECONDS:-86400}}"
QUIET=false
FORCE=false
CACHED_ONLY=false

for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=true ;;
        --force) FORCE=true ;;
        --cached-only) CACHED_ONLY=true ;;
        --help|-h)
            echo "Usage: check-update.sh [--quiet] [--force] [--cached-only]"
            echo "  --cached-only  Never use the network; read an existing cache only"
            exit 0
            ;;
        *) echo "error: unknown option: $arg" >&2; exit 2 ;;
    esac
done

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCAL_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
mkdir -p "$STATE_HOME"
cache="$STATE_HOME/remote-version"
cache_fresh=false
if ! $FORCE && [ -s "$cache" ]; then
    now="$(date +%s)"
    modified="$(date -r "$cache" +%s 2>/dev/null || printf '0')"
    [ "$((now - modified))" -lt "$CACHE_SECONDS" ] && cache_fresh=true
fi

if $CACHED_ONLY; then
    # Computer-use startup must never wait on DNS/network. A stale cached version
    # is still useful as an advisory; no cache simply means no startup notice.
    [ -s "$cache" ] || exit 0
elif ! $cache_fresh; then
    if ! command -v curl >/dev/null 2>&1; then
        $QUIET || echo "update check skipped: curl is unavailable"
        exit 0
    fi
    remote="$(curl -fsSL --connect-timeout 2 --max-time 4 "$BASE_URL/VERSION" 2>/dev/null || true)"
    remote="$(printf '%s' "$remote" | tr -d '[:space:]')"
    if [[ ! "$remote" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        $QUIET || echo "update check skipped: release endpoint is offline"
        exit 0
    fi
    printf '%s\n' "$remote" > "$cache"
fi

REMOTE_VERSION="$(tr -d '[:space:]' < "$cache")"
if [ "$REMOTE_VERSION" != "$LOCAL_VERSION" ] &&
   [ "$(printf '%s\n%s\n' "$LOCAL_VERSION" "$REMOTE_VERSION" | sort -V | tail -n1)" = "$REMOTE_VERSION" ]; then
    echo "gnome-wayland-computer-use update available: $LOCAL_VERSION -> $REMOTE_VERSION"
    echo "Reinstall: curl -fsSL $BASE_URL/install.sh | bash"
elif ! $QUIET; then
    echo "gnome-wayland-computer-use is current ($LOCAL_VERSION)"
fi
