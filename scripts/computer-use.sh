#!/usr/bin/env bash
# computer-use.sh — human-facing command surface used by Hermes /computer-use.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROFILE="$ROOT/scripts/profile.sh"
PORTAL="$ROOT/scripts/portal-control.py"
HEALTH="$ROOT/scripts/cua-health.py"
DIAGNOSE="$ROOT/scripts/diagnose.sh"
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3)"

usage() {
    cat <<'HELP'
/computer-use commands

  /computer-use status
      Compact Cua, RemoteDesktop, observer and managed-memory status.

  /computer-use managed
      Enable managed project AGENTS.md identity truths.

  /computer-use managed on|off|status
      Change or inspect project-local managed AGENTS.md routing memory.

  /computer-use consent
      Explain and verify the GNOME RemoteDesktop -> EIS/libei control path.

  /computer-use doctor
      Run the deterministic installed-system diagnosis.

  /computer-use help
      Show this command surface.
HELP
}

pretty_json() {
    "$PYTHON" - "$1" <<'PY'
import json,sys
try:d=json.loads(sys.argv[1])
except Exception:
    print(sys.argv[1]); raise SystemExit
print(json.dumps(d,indent=2,ensure_ascii=False))
PY
}

command="${1:-help}"
[ "$#" -eq 0 ] || shift
case "$command" in
    managed)
        mode="${1:-on}"
        case "$mode" in on|off|status) ;; *) printf 'managed expects on|off|status\n' >&2; exit 2 ;; esac
        out=$("$PROFILE" managed "$mode" --machine)
        "$PYTHON" - "$out" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); enabled=bool(d.get("managed_agents"))
print(f"Managed AGENTS.md blocks: {'ON' if enabled else 'OFF'}")
if enabled:
    print("Stable project app identities may be remembered in a bounded managed block.")
    print("A warm identity hit can remove 100% of the repeat identity-routing setup call.")
else:
    print("Project AGENTS.md files will not be written by GWCU.")
print(f"Preference: {d.get('path')}")
PY
        ;;
    consent)
        set +e; out=$("$PORTAL" --status 2>/dev/null); rc=$?; set -e
        [ -n "$out" ] || out='{"schema":"gwcu.portal-control.v1","ok":false,"code":"unavailable"}'
        "$PYTHON" - "$out" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); p=d.get('portal',{}); t=p.get('restore_token',{}); i=d.get('integration',{})
print("GNOME Remote Desktop control")
print(f"  portal interface: {'available' if p.get('available') else 'unavailable'}")
print(f"  purpose: {p.get('purpose','local pointer and keyboard delivery')}")
print("  transport: GNOME portal -> EIS -> libei")
print(f"  restore token: {'present' if t.get('present') else 'not established'}")
if t.get('path'): print(f"  token path: {t['path']}")
print(f"  GWCU RDP/VNC server: {'yes' if i.get('gwcu_rdp_or_vnc_server') else 'no'}")
print(f"  GWCU raw-input path: {'yes' if i.get('gwcu_raw_input_path') else 'no'}")
print(f"  GWCU control daemon: {'yes' if i.get('gwcu_control_service_present') else 'no'}")
print("This permission is GNOME's compositor-approved local input API; it is not a remote-login service.")
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
        set +e; portal=$("$PORTAL" --status 2>/dev/null); portal_rc=$?; set -e
        [ -n "$portal" ] || portal='{"schema":"gwcu.portal-control.v1","ok":false,"code":"unavailable"}'
        set +e; health=$("$HEALTH" 2>/dev/null); health_rc=$?; set -e
        [ -n "$health" ] || health='{"schema":"gwcu.cua-health.v1","ok":false,"code":"unavailable"}'
        "$PYTHON" - "$managed" "$portal" "$health" "$portal_rc" "$health_rc" <<'PY'
import json,sys
m=json.loads(sys.argv[1]); p=json.loads(sys.argv[2]); h=json.loads(sys.argv[3])
portal=p.get('portal',{}); token=portal.get('restore_token',{}); report=h.get('report') or {}
print("Computer use")
print(f"  Cua health: {report.get('overall') or h.get('code','unknown')}")
print(f"  RemoteDesktop portal: {'available' if portal.get('available') else 'unavailable'}")
print(f"  RemoteDesktop restore token: {'present' if token.get('present') else 'not established'}")
print(f"  managed AGENTS.md: {'on' if m.get('managed_agents') else 'off'}")
print("  control: Cua -> GNOME RemoteDesktop -> EIS/libei")
print("  whole-screen observation: XDG ScreenCast -> PipeWire")
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
