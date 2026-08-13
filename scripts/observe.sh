#!/usr/bin/env bash
# observe.sh — machine-first whole-screen observation facade.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OBSERVER="${GWCU_OBSERVER_BIN:-$SCRIPT_DIR/observer.py}"
DIRECT_CAPTURE="${GWCU_DIRECT_CAPTURE_BIN:-$SCRIPT_DIR/capture.sh}"
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"

MACHINE=false
MEDIA=false
TIMING=false
SCOPE=screen
FRESH=next
OUT=
START_MS=$(date +%s%3N 2>/dev/null || printf '0')

usage() {
    echo "usage: $0 [--machine] [--media] [--timing] [--fresh=next|latest] [--desktop|--screen] [output.png]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --machine) MACHINE=true ;;
        --media) MEDIA=true ;;
        --timing) TIMING=true ;;
        --desktop) SCOPE=desktop ;;
        --screen) SCOPE=screen ;;
        --fresh=next) FRESH=next ;;
        --fresh=latest) FRESH=latest ;;
        --help|-h) usage; exit 0 ;;
        -*) usage; exit 2 ;;
        *)
            [ -z "$OUT" ] || { usage; exit 2; }
            OUT="$1"
            ;;
    esac
    shift
done

[ -n "$PYTHON" ] || { echo "python3 is required" >&2; exit 30; }
OUT="${OUT:-${XDG_RUNTIME_DIR:-/tmp}/gnome-wayland-screen-$(date +%s).png}"
mkdir -p "$(dirname "$OUT")"

emit_machine_success() {
    local method="$1" source_json="${2:-}" now elapsed
    now=$(date +%s%3N 2>/dev/null || printf '0')
    elapsed=0
    if [[ "$START_MS" =~ ^[0-9]+$ ]] && [[ "$now" =~ ^[0-9]+$ ]] && [ "$now" -ge "$START_MS" ]; then
        elapsed=$((now - START_MS))
    fi
    "$PYTHON" - "$method" "$OUT" "$SCOPE" "$elapsed" "$source_json" <<'PY'
import json, sys
method, path, requested, elapsed, raw = sys.argv[1:]
source = None
if raw:
    try: source = json.loads(raw)
    except Exception: source = None
result = {"scope":"visible-screen","requested_scope":requested,"method":method,"path":path}
if source and isinstance(source.get("result"), dict):
    for key in ("width","height","freshness_ms","stream_generation"):
        if key in source["result"]: result[key] = source["result"][key]
payload = {"schema":"gwcu.observe.v1","ok":True,"code":"ok","result":result,"timing_ms":{"total":int(elapsed)},"next":None}
if source and "timing_ms" in source: payload["broker_timing_ms"] = source["timing_ms"]
print(json.dumps(payload,separators=(",",":")))
PY
}

emit_machine_failure() {
    local code="$1" exit_class="$2" terminal="$3" retryable="$4" detail="${5:-}" next="${6:-}"
    "$PYTHON" - "$code" "$terminal" "$retryable" "$detail" "$next" <<'PY'
import json, sys
code, terminal, retryable, detail, next_action = sys.argv[1:]
p={"schema":"gwcu.observe.v1","ok":False,"code":code,"retryable":retryable=="true","terminal":terminal=="true","next":None}
if detail: p["detail"]=detail
if next_action: p["next"]={"action":next_action}
print(json.dumps(p,separators=(",",":")))
PY
    return "$exit_class"
}

report_human() {
    local method="$1" now elapsed
    [ "$SCOPE" = desktop ] && printf 'capture_scope=visible-screen requested=desktop\n' >&2 || true
    if $TIMING; then
        now=$(date +%s%3N 2>/dev/null || printf '0')
        if [[ "$START_MS" =~ ^[0-9]+$ ]] && [[ "$now" =~ ^[0-9]+$ ]] && [ "$now" -ge "$START_MS" ]; then
            elapsed=$((now - START_MS)); printf 'capture_elapsed_ms=%s\n' "$elapsed" >&2
        fi
    fi
    if $MEDIA; then
        printf 'MEDIA:%s\n' "$OUT"; printf 'capture_method=%s\n' "$method" >&2
    else
        printf 'capture_method=%s\n' "$method"
    fi
}

copy_broker_frame() {
    local raw="$1" src tmp
    src=$("$PYTHON" - "$raw" <<'PY'
import json, sys
try: print(json.loads(sys.argv[1]).get("result",{}).get("path",""))
except Exception: pass
PY
)
    [ -n "$src" ] && [ -s "$src" ] || return 1
    tmp=$(mktemp "$(dirname "$OUT")/.observe.XXXXXX.png")
    cp "$src" "$tmp"; chmod 600 "$tmp" 2>/dev/null || true; mv -f "$tmp" "$OUT"
}

broker_capture() {
    local raw rc=0
    raw=$("$PYTHON" "$OBSERVER" client capture --fresh "$FRESH" --timeout-ms 1500) || rc=$?
    printf '%s' "$raw"; return "$rc"
}

broker_raw=""; broker_rc=0
broker_raw=$(broker_capture) || broker_rc=$?
if [ "$broker_rc" -eq 30 ] && command -v systemctl >/dev/null 2>&1; then
    systemctl --user start gnome-wayland-computer-use-observer.socket >/dev/null 2>&1 || true
    sleep 0.02
    broker_rc=0; broker_raw=$(broker_capture) || broker_rc=$?
fi

if [ "$broker_rc" -eq 0 ] && copy_broker_frame "$broker_raw"; then
    $MACHINE && emit_machine_success "screencast-broker" "$broker_raw" || report_human "screencast-broker"
    exit 0
fi

if [ "$broker_rc" -eq 20 ]; then
    code=$("$PYTHON" - "$broker_raw" <<'PY'
import json, sys
try: print(json.loads(sys.argv[1]).get("code","portal_cancelled"))
except Exception: print("portal_cancelled")
PY
)
    if $MACHINE; then emit_machine_failure "$code" 20 true false "ScreenCast interaction did not complete"; else echo "capture_method=portal-denied" >&2; fi
    exit 20
fi

direct_stdout=$(mktemp); direct_stderr=$(mktemp)
trap 'rm -f "$direct_stdout" "$direct_stderr"' EXIT
direct_rc=0
"$DIRECT_CAPTURE" --"$SCOPE" "$OUT" >"$direct_stdout" 2>"$direct_stderr" || direct_rc=$?

if [ "$direct_rc" -eq 0 ] && [ -s "$OUT" ]; then
    method=$(sed -n 's/^capture_method=//p' "$direct_stdout" | tail -1); method="${method:-direct-capture}"
    $MACHINE && emit_machine_success "${method}-direct" "" || report_human "$method"
    exit 0
fi
if grep -q 'capture_method=portal-denied' "$direct_stderr"; then
    if $MACHINE; then emit_machine_failure "portal_cancelled" 20 true false "ScreenCast interaction did not complete"; else cat "$direct_stderr" >&2; fi
    exit 20
fi
if $MACHINE; then
    detail=$(tail -c 1024 "$direct_stderr" 2>/dev/null || true)
    emit_machine_failure "observation_unavailable" 40 false true "$detail" "diagnose_observation"
else
    cat "$direct_stderr" >&2; echo "capture_method=failed" >&2
fi
exit 40
