#!/usr/bin/env bash
# diagnose.sh — capability-oriented diagnostic for gnome-wayland-computer-use
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/lib/checks.sh"
JSON=false; MACHINE=false; FAILED=0
for arg in "$@"; do case "$arg" in --json) JSON=true;; --machine) MACHINE=true;; --help|-h) echo "usage: $0 [--json|--machine]"; exit 0;; esac; done
if $MACHINE; then
 tmp=$(mktemp); trap 'rm -f "$tmp"' EXIT; "$0" --json >"$tmp" || true
 python="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"; [ -x "$python" ] || python="$(command -v python3 2>/dev/null || true)"; [ -n "$python" ] || exit 50
 exec "$python" - "$tmp" <<'PY'
import json,os,pathlib,sys
rows=[json.loads(x) for x in pathlib.Path(sys.argv[1]).read_text().splitlines() if x.strip()]
checks={};caps={}
for r in rows:
 if 'check' in r and r['check']!='summary':checks[r['check']]={'pass':bool(r.get('pass')),'detail':r.get('detail','')}
 if 'capability' in r:caps[r['capability']]=r.get('status','UNKNOWN').lower().replace(' ','_')
host={'session':checks.get('session',{}).get('detail') or os.environ.get('XDG_SESSION_TYPE'),'desktop':checks.get('desktop',{}).get('detail') or os.environ.get('XDG_CURRENT_DESKTOP')}
n=None
if caps.get('gnome_precision')=='reload_required':n={'action':'logout_login','reason':'activate_gnome_precision'}
elif caps.get('observation')=='degraded':n={'action':'repair_observation'}
elif caps.get('semantic_control')=='degraded':n={'action':'repair_semantics'}
elif caps.get('gnome_precision')=='degraded':n={'action':'repair_cua'}
elif caps.get('input_recovery')=='degraded':n={'action':'repair_recovery'}
p={'schema':'gwcu.diagnose.v1','ok':True,'code':'ok','host':host,'capabilities':{'observation':{'status':caps.get('observation','unknown')},'semantics':{'status':caps.get('semantic_control','unknown')},'gnome_precision':{'status':caps.get('gnome_precision','unknown')},'recovery':{'status':caps.get('input_recovery','unknown')}},'checks':checks,'next':n}
print(json.dumps(p,separators=(',',':')))
PY
fi
json_escape(){ local v="$1"; v=${v//\\/\\\\}; v=${v//\"/\\\"}; v=${v//$'\n'/\\n}; v=${v//$'\r'/\\r}; v=${v//$'\t'/\\t}; printf '%s' "$v"; }
check_and_report(){ local name="$1" detail="${2:-}"; shift 2; local rc=0; if $JSON; then "$@" >/dev/null 2>&1 || rc=$?; printf '{"check":"%s","pass":%s,"detail":"%s"}\n' "$(json_escape "$name")" "$([ "$rc" -eq 0 ] && echo true || echo false)" "$(json_escape "$detail")"; else "$@" || rc=$?; fi; [ "$rc" -eq 0 ] || ((FAILED++)) || true; return 0; }
observation_status(){ check_is_screencast_portal_ready && check_is_pipewire_core_ready && check_is_wireplumber_ready && check_is_pipewire_capture_ready && echo READY || echo DEGRADED; }
semantic_status(){ check_is_toolkit_accessibility_enabled && check_is_atspi_bus_alive && check_is_atspi_socket_exists && echo READY || echo DEGRADED; }
precision_status(){ if ! check_is_hermes_integration_enabled; then echo 'NOT SELECTED'; return; fi; if check_is_cua_driver_running && check_is_cua_winrects_active && check_is_winrects_served_by_gnome_shell; then echo READY; elif check_is_cua_winrects_installed && ! check_is_cua_winrects_active; then echo 'RELOAD REQUIRED'; else echo DEGRADED; fi; }
input_status(){ check_has_uinput_device && check_is_input_group_member && { check_is_ydotoold_running || check_is_ydotoold_process_up; } && echo READY || echo DEGRADED; }
if ! $JSON; then echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo "  gnome-wayland-computer-use diagnose"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; echo ""; fi
$JSON || { check_hr; echo "── Desktop"; }
check_and_report session "$(check_get_session)" check_session
check_and_report desktop "$(check_get_desktop)" check_desktop
check_and_report gnome_shell "" check_gnome_shell
check_and_report xwayland "" check_xwayland
$JSON || { echo ""; check_hr; echo "── Observation"; }
check_and_report screencast_portal hot_path check_screencast_portal
check_and_report pipewire_core ubuntu_foundation check_pipewire_core
check_and_report wireplumber ubuntu_foundation check_wireplumber
check_and_report pipewire_capture gstreamer_bridge check_pipewire_capture
check_and_report screenshot_portal recovery check_screenshot_portal
RESTORE_DETAIL=uncached; check_has_screencast_restore_token && RESTORE_DETAIL=cached
check_and_report screencast_restore_token "$RESTORE_DETAIL" check_restore_token
observer_socket="$HOME/.config/systemd/user/gnome-wayland-computer-use-observer.socket"
check_and_report observer_socket lazy_persistent_optimization test -f "$observer_socket"
$JSON || { echo ""; check_hr; echo "── Semantic control"; }
check_and_report toolkit_accessibility "" check_toolkit_accessibility
check_and_report atspi_bus "" check_atspi_bus
check_and_report atspi_socket "" check_atspi_socket
check_and_report skill "" check_skill
check_and_report hermes_skill "" check_hermes_skill
$JSON || { echo ""; check_hr; echo "── Cua GNOME precision"; }
check_and_report cua_driver runtime check_cua_driver
check_and_report cua_wayland_helper package_owned check_cua_helper_package
check_and_report cua_winrects_installed code_owned_by_cua check_cua_winrects_installed
check_and_report cua_winrects_active session_state check_cua_winrects_active
check_and_report cua_winrects_shell_owner focus_and_geometry_trust check_cua_winrects_bus
$JSON || { echo ""; check_hr; echo "── Input recovery"; }
check_and_report uinput last_resort check_uinput
check_and_report input_group last_resort check_input_group
check_and_report ydotoold last_resort check_ydotoold
$JSON || { echo ""; check_hr; echo "── Migration"; }
check_and_report legacy_capture_extension must_be_absent check_legacy_capture_extension
OBSERVATION=$(observation_status); SEMANTIC=$(semantic_status); PRECISION=$(precision_status); INPUT=$(input_status)
if $JSON; then
 printf '{"capability":"observation","status":"%s"}\n' "$OBSERVATION"
 printf '{"capability":"semantic_control","status":"%s"}\n' "$SEMANTIC"
 printf '{"capability":"gnome_precision","status":"%s"}\n' "$PRECISION"
 printf '{"capability":"input_recovery","status":"%s"}\n' "$INPUT"
 printf '{"check":"summary","pass":%s,"detail":"capability-oriented"}\n' "$([ "$FAILED" -eq 0 ] && echo true || echo false)"
else
 echo ""; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"; printf '  Observation:       %s\n' "$OBSERVATION"; printf '  Semantic control:  %s\n' "$SEMANTIC"; printf '  GNOME precision:   %s\n' "$PRECISION"; printf '  Input recovery:    %s\n' "$INPUT"; echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi
[ "$FAILED" -eq 0 ]
