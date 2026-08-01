#!/usr/bin/env bash
set -euo pipefail

NAME="gnome-wayland-computer-use"
BASE_URL="${GNOME_WAYLAND_COMPUTER_USE_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
STATE_HOME="${GNOME_WAYLAND_COMPUTER_USE_UPDATE_STATE_HOME:-${XDG_STATE_HOME:-$HOME/.local/state}/$NAME/update}"
CACHE_SECONDS="${GNOME_WAYLAND_COMPUTER_USE_UPDATE_CACHE_SECONDS:-86400}"
QUIET=false
FORCE=false

for arg in "$@"; do
    case "$arg" in
        --quiet) QUIET=true ;;
        --force) FORCE=true ;;
        --help|-h) echo "Usage: check-update.sh [--quiet] [--force]"; exit 0 ;;
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

if ! $cache_fresh; then
    if ! command -v curl >/dev/null 2>&1; then
        $QUIET || echo "update check skipped: curl is unavailable"
        exit 0
    fi
    remote="$(curl -fsSL --connect-timeout 3 --max-time 8 "$BASE_URL/VERSION" 2>/dev/null || true)"
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
