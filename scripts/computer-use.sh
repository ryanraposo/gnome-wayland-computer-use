#!/usr/bin/env bash
# computer-use.sh — installed GWCU command/composition surface.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="$ROOT/scripts/profile.sh"
PORTAL="$ROOT/scripts/portal-control.py"
HEALTH="$ROOT/scripts/cua-health.py"
DIAGNOSE="$ROOT/scripts/diagnose.sh"
ACTION_SPAN="$ROOT/scripts/action-span.py"
WORLDLINE="$ROOT/scripts/worldline.py"
PRESENTER="$ROOT/scripts/present-window.py"
PYTHON="${GWCU_SYSTEM_PYTHON:-${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use"
BACKGROUND_PREF="$STATE_DIR/background-priority"

usage() {
    cat <<'HELP'
/computer-use commands

  /computer-use status
      Compact Cua, presentation, WORLDLINE, consent, observer and .gwcu status.

  /computer-use trace
      Print the exact default foreground execution path agents must follow.

  /computer-use present --pid PID --window-id ID
      Persistently focus + raise one exact Cua/GNOME window and prove it.

  /computer-use background [on|off|status]
      Set background priority. Default OFF = exact visible takeover.

  /computer-use managed [on|off|status]
      Control repo/workspace-local .gwcu persistence.

  /computer-use truths
      Show the current .gwcu scope and stored truth counts.

  /computer-use consent
      Explain and verify GNOME RemoteDesktop -> EIS/libei control consent.

  /computer-use doctor
      Run deterministic installed-system diagnosis.

  computer-use.sh span --actions-json '<json>'
      Execute an already-decided Cua action span behind ONE model/tool boundary.

  /computer-use help
      Show this command surface.
HELP
}

pretty_json() {
    "$PYTHON" - "$1" <<'PY'
import json,sys
try: d=json.loads(sys.argv[1])
except Exception:
    print(sys.argv[1]); raise SystemExit
print(json.dumps(d,indent=2,ensure_ascii=False))
PY
}

background_value() {
    local value="${GWCU_BACKGROUND_PRIORITY:-}"
    if [ -z "$value" ] && [ -s "$BACKGROUND_PREF" ]; then IFS= read -r value <"$BACKGROUND_PREF" || value=""; fi
    case "${value,,}" in on|yes|true|1|background) printf 'on\n';; *) printf 'off\n';; esac
}

write_background() {
    local value="$1" tmp
    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" 2>/dev/null || true
    tmp=$(mktemp "$STATE_DIR/.background-priority.XXXXXX")
    printf '%s\n' "$value" >"$tmp"; chmod 600 "$tmp"; mv -f "$tmp" "$BACKGROUND_PREF"
}

show_background() {
    local value source
    value=$(background_value); source=default
    [ -s "$BACKGROUND_PREF" ] && source=saved
    [ -n "${GWCU_BACKGROUND_PRIORITY:-}" ] && source=environment
    if [ "$value" = on ]; then
        printf 'Background computer use: ON\n'
        printf '  priority: background where Cua can address the exact target safely\n'
        printf '  visible-result tasks: exact presentation is still a final postcondition\n'
        printf '  fallback: explicit foreground only when Cua reports background unavailable\n'
    else
        printf 'Background computer use: OFF\n'
        printf '  priority: EXACT VISIBLE TAKEOVER\n'
        printf '  gate: exact (pid, window_id) -> attested Cua GNOME helper -> focused+visible proof\n'
        printf '  input: Cua foreground delivery only after that gate succeeds\n'
        printf '  completion: re-present + verify exact target; leave it visible\n'
    fi
    printf '  source: %s\n' "$source"
}

worldline_status() {
    local out rc=0
    set +e
    out=$("$PYTHON" "$WORLDLINE" request --json '{"op":"status"}' 2>/dev/null)
    rc=$?
    set -e
    [ -n "$out" ] || out='{"schema":"gwcu.worldline.v1","ok":false,"code":"unavailable"}'
    printf '%s\n' "$out"
    return "$rc"
}

show_trace() {
    cat <<'TRACE'
Default foreground trace (background priority OFF)

  1. DISCOVER
     Cua list_windows resolves the intended native target to exact (pid, window_id).
     No title-only actuation. Ambiguity is resolved before input.

  2. PRESENT
     GWCU calls Cua's installed GNOME Shell helper for that stable window id.
     GNOME must report that exact pid/window_id focused, visible, and not minimized.
     Failure here is terminal for the action: no global input is sent.

  3. ACT
     Cua performs the mutation against the same exact target with
     delivery_mode=foreground. Because the target is already the focused window,
     Cua's action-scoped foreground restore resolves back to that same target.

  4. REVALIDATE
     If an action creates, closes, replaces, or navigates the native target,
     resolve its current exact identity before the next focus-bound mutation.

  5. COMPLETE VISIBLY
     Re-present the final exact target, verify focused+visible again, then verify
     the requested application/page state. Leave the intended result on screen.

Typed Chromium/Electron route
  Resolve exact native (pid, window_id) -> PRESENT -> exact cua_browser_state bind
  -> fresh semantic snapshot -> typed mutation -> fresh snapshot -> PRESENT/verify.
  Typed browser success never substitutes for native visible presentation.

Background priority ON is the explicit opt-out from persistent takeover for
ordinary work. A user-visible result still ends at step 5.
TRACE
}

command="${1:-help}"
[ "$#" -eq 0 ] || shift
case "$command" in
    span)
        exec "$PYTHON" "$ACTION_SPAN" "$@"
        ;;
    trace)
        show_trace
        ;;
    present)
        exec "$PYTHON" "$PRESENTER" present "$@"
        ;;
    background)
        mode="${1:-toggle}"
        case "${mode,,}" in
            toggle) [ "$(background_value)" = on ] && write_background off || write_background on ;;
            on|yes|true|1) write_background on ;;
            off|no|false|0) write_background off ;;
            status) ;;
            *) printf 'background expects on|off|status (or no argument to toggle)\n' >&2; exit 2 ;;
        esac
        show_background
        ;;
    managed)
        mode="${1:-on}"
        case "$mode" in on|off|status) ;; *) printf 'managed expects on|off|status\n' >&2; exit 2 ;; esac
        out=$("$PROFILE" managed "$mode" --machine)
        "$PYTHON" - "$out" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); enabled=bool(d.get("managed_truths")); s=d.get('scope') or {}
print(f"Managed .gwcu truths: {'ON' if enabled else 'OFF'}")
if enabled:
    print("Stable local facts may be remembered in the current repo/workspace .gwcu.")
    print("Git scopes keep /.gwcu in the root .gitignore before truth is written.")
else:
    print("GWCU will not read or write persisted .gwcu truths on the hot path.")
if s.get('path'): print(f"Current truth file: {s['path']}")
print(f"Preference: {d.get('path')}")
PY
        ;;
    truths)
        set +e; out=$("$PROFILE" truths status --machine); rc=$?; set -e
        [ -n "$out" ] || out='{"schema":"gwcu.truths.v1","ok":false,"code":"unavailable"}'
        "$PYTHON" - "$out" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); c=d.get('counts') or {}
print(".gwcu truths")
print(f"  status: {d.get('code','unknown')}")
if d.get('root'): print(f"  scope: {d['root']}")
if d.get('path'): print(f"  file: {d['path']}")
print(f"  git scope: {'yes' if d.get('git') else 'no'}")
for label,key in (("apps","apps"),("observed facts","observed"),("capabilities","capabilities"),("calibration","calibration"),("preferences","preferences")):
    if c: print(f"  {label}: {c.get(key,0)}")
PY
        exit 0
        ;;
    consent)
        set +e; out=$("$PORTAL" --status 2>/dev/null); rc=$?; set -e
        [ -n "$out" ] || out='{"schema":"gwcu.portal-control.v1","ok":false,"code":"unavailable"}'
        "$PYTHON" - "$out" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); p=d.get('portal',{}); t=p.get('restore_token',{}); i=d.get('integration',{})
print("GNOME Remote Desktop control")
print(f"  portal interface: {'available' if p.get('available') else 'unavailable'}")
print("  transport: GNOME portal -> EIS -> libei")
print(f"  restore token: {'present' if t.get('present') else 'not established'}")
if t.get('path'): print(f"  token path: {t['path']}")
print(f"  GWCU RDP/VNC server: {'yes' if i.get('gwcu_rdp_or_vnc_server') else 'no'}")
print(f"  GWCU raw-input path: {'yes' if i.get('gwcu_raw_input_path') else 'no'}")
print(f"  GWCU control daemon: {'yes' if i.get('gwcu_control_service_present') else 'no'}")
print("Cua is the only actuator; WORLDLINE is read-only state/predicate machinery.")
PY
        exit 0
        ;;
    doctor)
        set +e; out=$("$DIAGNOSE" --machine); rc=$?; set -e
        pretty_json "$out"
        exit "$rc"
        ;;
    status)
        managed=$("$PROFILE" managed status --machine)
        background=$(background_value)
        set +e
        portal=$("$PORTAL" --status 2>/dev/null); portal_rc=$?
        health=$("$HEALTH" 2>/dev/null); health_rc=$?
        worldline=$(worldline_status); worldline_rc=$?
        presentation=$("$PYTHON" "$PRESENTER" status 2>/dev/null); presentation_rc=$?
        set -e
        [ -n "$portal" ] || portal='{"schema":"gwcu.portal-control.v1","ok":false,"code":"unavailable"}'
        [ -n "$health" ] || health='{"schema":"gwcu.cua-health.v1","ok":false,"code":"unavailable"}'
        [ -n "$worldline" ] || worldline='{"schema":"gwcu.worldline.v1","ok":false,"code":"unavailable"}'
        [ -n "$presentation" ] || presentation='{"schema":"gwcu.presentation.v1","ok":false,"code":"unavailable"}'
        "$PYTHON" - "$managed" "$portal" "$health" "$worldline" "$presentation" "$background" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); p=json.loads(sys.argv[2]); h=json.loads(sys.argv[3]); w=json.loads(sys.argv[4]); pr=json.loads(sys.argv[5]); background=sys.argv[6]=='on'
portal=p.get('portal',{}); token=portal.get('restore_token',{}); report=h.get('report') or {}; scope=m.get('scope') or {}
state=w.get('state') if isinstance(w.get('state'),dict) else w
print("Computer use")
print(f"  Cua health: {report.get('overall') or h.get('code','unknown')}")
print(f"  exact presentation: {pr.get('code','unavailable')} (helper API {pr.get('helper_api','?')})")
print(f"  WORLDLINE: {w.get('code','ready') if w.get('ok') else w.get('code','unavailable')}")
if isinstance(state,dict) and state.get('revision') is not None: print(f"  WORLDLINE revision: {state.get('revision')}")
print(f"  control priority: {'background' if background else 'exact visible takeover'}")
print(f"  RemoteDesktop portal: {'available' if portal.get('available') else 'unavailable'}")
print(f"  RemoteDesktop restore token: {'present' if token.get('present') else 'not established'}")
print(f"  managed .gwcu: {'on' if m.get('managed_truths') else 'off'}")
if scope.get('path'): print(f"  truth file: {scope['path']}")
print("  default foreground: exact target -> Cua GNOME presentation gate -> Cua input -> visible proof")
print("  runtime truth: AT-SPI/direct oracles -> WORLDLINE")
print("  visual escalation: XDG ScreenCast -> PipeWire observer -> WORLDLINE")
PY
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        printf 'Unknown /computer-use command: %s\n\n' "$command" >&2
        usage >&2
        exit 2
        ;;
esac
