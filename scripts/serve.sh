#!/usr/bin/env bash
# Long-running cua-driver compatibility backend used by the Hermes integration.
set -euo pipefail

# Hermes now owns its own MCP/embedded cua-driver lifecycle. Keep this legacy
# service cheap when installed, and also seed the settings Hermes itself reads
# before it spawns its driver.
if command -v hermes >/dev/null 2>&1; then
    hermes config set computer_use.no_overlay true >/dev/null 2>&1 || true
    hermes config set computer_use.max_image_dimension 1152 >/dev/null 2>&1 || true
fi

# Cua Driver telemetry is unnecessary work for this local desktop integration.
export CUA_DRIVER_RS_TELEMETRY_ENABLED=0

DRIVER="${CUA_DRIVER_BIN:-}"
if [ -z "$DRIVER" ]; then
    DRIVER=$(command -v cua-driver || true)
fi
if [ -z "$DRIVER" ]; then
    printf 'cua-driver is not installed (Hermes can install it with: hermes computer-use install)\n' >&2
    exit 127
fi

exec "$DRIVER" serve --no-overlay
