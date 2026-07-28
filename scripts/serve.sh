#!/usr/bin/env bash
# Long-running backend used by Hermes's computer_use tool on Linux.
set -euo pipefail

DRIVER="${CUA_DRIVER_BIN:-}"
if [ -z "$DRIVER" ]; then
    DRIVER=$(command -v cua-driver || true)
fi
if [ -z "$DRIVER" ]; then
    printf 'cua-driver is not installed; run: hermes computer-use install\n' >&2
    exit 127
fi

exec "$DRIVER" serve --no-overlay
