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
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3)"

usage() {
    cat <<'HELP'
/computer-use commands

  /computer-use status
      Compact Cua, WORLDLINE, RemoteDesktop, observer and .gwcu status.

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

command="${1:-help}"
[ "$#" -eq 0 ] || shift
case "$command" in
    span)
        # Hard invariant: this is ONE model/tool boundary for the entire already-decided span.
        # Cua remains the sole control authority; this wrapper adds no alternate input path.
        exec "$PYTHON" "$ACTION_SPAN" "$@"
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
        set +e
        portal=$("$PORTAL" --status 2>/dev/null); portal_rc=$?
        health=$("$HEALTH" 2>/dev/null); health_rc=$?
        worldline=$(worldline_status); worldline_rc=$?
        set -e
        [ -n "$portal" ] || portal='{"schema":"gwcu.portal-control.v1","ok":false,"code":"unavailable"}'
        [ -n "$health" ] || health='{"schema":"gwcu.cua-health.v1","ok":false,"code":"unavailable"}'
        [ -n "$worldline" ] || worldline='{"schema":"gwcu.worldline.v1","ok":false,"code":"unavailable"}'
        "$PYTHON" - "$managed" "$portal" "$health" "$worldline" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); p=json.loads(sys.argv[2]); h=json.loads(sys.argv[3]); w=json.loads(sys.argv[4])
portal=p.get('portal',{}); token=portal.get('restore_token',{}); report=h.get('report') or {}; scope=m.get('scope') or {}
state=w.get('state') if isinstance(w.get('state'),dict) else w
print("Computer use")
print(f"  Cua health: {report.get('overall') or h.get('code','unknown')}")
print(f"  WORLDLINE: {w.get('code','ready') if w.get('ok') else w.get('code','unavailable')}")
if isinstance(state,dict):
    if state.get('revision') is not None: print(f"  WORLDLINE revision: {state.get('revision')}")
    facts=state.get('facts')
    if isinstance(facts,dict): print(f"  live facts: {len(facts)}")
print(f"  RemoteDesktop portal: {'available' if portal.get('available') else 'unavailable'}")
print(f"  RemoteDesktop restore token: {'present' if token.get('present') else 'not established'}")
print(f"  managed .gwcu: {'on' if m.get('managed_truths') else 'off'}")
if scope.get('path'): print(f"  truth file: {scope['path']}")
print("  control: Cua -> GNOME RemoteDesktop -> EIS/libei")
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
