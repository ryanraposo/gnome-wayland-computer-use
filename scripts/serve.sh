#!/usr/bin/env bash
# Long-running cua-driver backend used by the Hermes integration on Linux.
set -euo pipefail

DRIVER="${CUA_DRIVER_BIN:-}"
if [ -z "$DRIVER" ]; then
    DRIVER=$(command -v cua-driver || true)
fi
if [ -z "$DRIVER" ]; then
    printf 'cua-driver is not installed (Hermes can install it with: hermes computer-use install)\n' >&2
    exit 127
fi

exec "$DRIVER" serve --no-overlay
