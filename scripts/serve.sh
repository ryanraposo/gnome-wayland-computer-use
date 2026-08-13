#!/usr/bin/env bash
# Long-running cua-driver backend used by the Hermes integration on Linux.
set -euo pipefail
DRIVER="${CUA_DRIVER_BIN:-}"
[ -n "$DRIVER" ] || DRIVER=$(command -v cua-driver 2>/dev/null || true)
[ -n "$DRIVER" ] || [ ! -x "$HOME/.local/bin/cua-driver" ] || DRIVER="$HOME/.local/bin/cua-driver"
[ -n "$DRIVER" ] || { printf 'cua-driver is not installed (run the official Cua Driver installer)\n' >&2; exit 127; }
exec "$DRIVER" serve --no-overlay
