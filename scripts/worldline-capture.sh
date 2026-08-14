#!/usr/bin/env bash
# worldline-capture.sh — one WORLDLINE revision boundary.
#
# This is the shell-shaped executable contract for:
#
#   stamp boundary
#   drain queued semantic/system events
#   refresh cheap direct oracles
#   optionally take the first fresh PipeWire frame
#   correlate + invalidate
#   evaluate postconditions
#   seal revision
#   wake ready transactions
#
# The model is not part of this loop. Cua remains the sole control authority.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3)"

TRIGGER="manual"
VISUAL=false
EXPECT='[]'
INVALIDATES='[]'
PIDS='[]'
PATHS='[]'
CONFLICT=false

usage() {
    cat <<'HELP'
Usage: worldline-capture.sh [options]

  --trigger <name>          revision cause, e.g. action:click
  --visual                  require a fresh ScreenCast/PipeWire frame
  --expect-json <array>     predicates to evaluate in this revision
  --invalidate-json <array> fact paths invalidated by the triggering action
  --pids-json <array>       process IDs to sample through /proc
  --paths-json <array>      files/paths to sample through stat
  --conflict-on-miss        unsatisfied postconditions become conflicts

Predicate example:
  [{"id":"dark","path":"settings.color_scheme","op":"eq","value":"prefer-dark"}]

The output is gwcu.worldline.revision.v1 JSON.
HELP
}

while [ $# -gt 0 ]; do
    case "$1" in
        --trigger) TRIGGER="${2:?missing trigger}"; shift ;;
        --visual) VISUAL=true ;;
        --expect-json) EXPECT="${2:?missing predicate array}"; shift ;;
        --invalidate-json) INVALIDATES="${2:?missing invalidation array}"; shift ;;
        --pids-json) PIDS="${2:?missing pid array}"; shift ;;
        --paths-json) PATHS="${2:?missing path array}"; shift ;;
        --conflict-on-miss) CONFLICT=true ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'unknown option: %s\n' "$1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

REQUEST="$("$PYTHON" - "$TRIGGER" "$VISUAL" "$EXPECT" "$INVALIDATES" "$PIDS" "$PATHS" "$CONFLICT" <<'PY'
import json,sys
trigger,visual,expect,invalidates,pids,paths,conflict=sys.argv[1:]
payload={
    "op":"capture",
    "trigger":trigger,
    "visual":visual=="true",
    "expect":json.loads(expect),
    "invalidates":json.loads(invalidates),
    "pids":json.loads(pids),
    "paths":json.loads(paths),
    "conflict_on_unsatisfied":conflict=="true",
}
print(json.dumps(payload,separators=(",",":")))
PY
)"

exec "$PYTHON" "$ROOT/scripts/worldline.py" request --json "$REQUEST"
