#!/usr/bin/env bash
# diagnose.sh — one compact verdict: presentation + observation + WORLDLINE + Cua health.
set -euo pipefail
MACHINE=false
for arg in "$@"; do
    case "$arg" in
        --machine|--json) MACHINE=true ;;
        --help|-h) echo "usage: $0 [--machine|--json]"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${GWCU_SYSTEM_PYTHON:-${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
[ -n "$PYTHON" ] || { echo "python3 is required" >&2; exit 30; }
HEALTH="$ROOT/scripts/cua-health.py"
WORLDLINE="$ROOT/scripts/worldline.py"
PRESENTER="$ROOT/scripts/present-window.py"

set +e
OUTPUT=$(
"$PYTHON" - "$HEALTH" "$WORLDLINE" "$PRESENTER" <<'PY'
import json, os, pathlib, shutil, subprocess, sys
health_script,worldline_script,presenter_script=sys.argv[1:4]

def run(argv, timeout=8):
    try:
        p=subprocess.run(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=timeout)
        return p.returncode,p.stdout.strip(),p.stderr.strip()
    except (OSError,subprocess.TimeoutExpired) as e:
        return 127,"",str(e)

def portal(name):
    if not shutil.which("gdbus"): return False
    rc,out,_=run(["gdbus","introspect","--session","--dest","org.freedesktop.portal.Desktop","--object-path","/org/freedesktop/portal/desktop"],4)
    return rc==0 and f"interface org.freedesktop.portal.{name}" in out

def active_unit(name):
    if not shutil.which("systemctl"): return False
    return run(["systemctl","--user","is-active","--quiet",name],3)[0]==0

def extension_active(uuid):
    if not shutil.which("gnome-extensions"): return False
    rc,out,_=run(["gnome-extensions","info",uuid],3)
    return rc==0 and "State:" in out and "ACTIVE" in out

session=os.environ.get("XDG_SESSION_TYPE") or "unknown"
desktop=os.environ.get("XDG_CURRENT_DESKTOP") or "unknown"
host_ok=session=="wayland" and "GNOME" in desktop
pw=run(["pw-cli","info","0"],3)[0]==0 if shutil.which("pw-cli") else False
wp=active_unit("wireplumber.service")
gst_pipewire=run(["gst-inspect-1.0","pipewiresrc"],3)[0]==0 if shutil.which("gst-inspect-1.0") else False
gst_png=run(["gst-inspect-1.0","pngenc"],3)[0]==0 if shutil.which("gst-inspect-1.0") else False
screen=portal("ScreenCast"); screenshot=portal("Screenshot")
observer=active_unit("gnome-wayland-computer-use-observer.socket")
observation_ok=all((pw,wp,gst_pipewire,gst_png,screen,observer))

worldline_socket=active_unit("gnome-wayland-computer-use-worldline.socket")
worldline_rc,worldline_out,worldline_err=run([sys.executable,worldline_script,"request","--json",'{"op":"status"}'],5)
try: worldline=json.loads(worldline_out) if worldline_out else None
except Exception: worldline={"ok":False,"code":"invalid_output","detail":worldline_out[:1024]}
worldline_ok=worldline_socket and worldline_rc==0 and isinstance(worldline,dict) and bool(worldline.get("ok"))

winrects_dir=pathlib.Path(os.environ.get("XDG_DATA_HOME",str(pathlib.Path.home()/".local/share")))/"gnome-shell/extensions/winrects@cua"
winrects_installed=winrects_dir.is_dir(); winrects_active=extension_active("winrects@cua")
presentation_rc,presentation_out,presentation_err=run([sys.executable,presenter_script,"status"],5) if winrects_active else (30,"","")
try: presentation=json.loads(presentation_out) if presentation_out else None
except Exception: presentation={"ok":False,"code":"invalid_output","detail":presentation_out[:1024]}
presentation_ok=winrects_active and presentation_rc==0 and isinstance(presentation,dict) and bool(presentation.get("ok"))

cua=shutil.which("cua-driver")
if not cua:
    candidate=pathlib.Path.home()/".local/bin/cua-driver"
    if candidate.is_file() and os.access(candidate,os.X_OK): cua=str(candidate)
health=None; health_rc=50; doctor=None; doctor_rc=127
if cua:
    health_rc,out,_=run([sys.executable,health_script,"--driver",cua],20)
    if out:
        try: health=json.loads(out)
        except Exception: health={"schema":"gwcu.cua-health.v1","ok":False,"code":"invalid_output","detail":out[:4096]}
    doctor_rc,out,_=run([cua,"doctor","--json"],15)
    if out:
        try: doctor=json.loads(out)
        except Exception: doctor={"raw":out[:4096]}

health_code=(health or {}).get("code","unavailable")
if winrects_installed and not winrects_active and host_ok:
    cua_status="reload_required"
elif health_rc==0 and winrects_active:
    cua_status="ready"
elif health_code=="failed":
    cua_status="failed"
else:
    cua_status="degraded"

ready=host_ok and observation_ok and worldline_ok and presentation_ok and cua_status=="ready"
if ready:
    code="ready"; nxt=None
elif cua_status=="reload_required" and observation_ok and worldline_ok:
    code="reload_required"; nxt={"action":"logout_login","reason":"activate_cua_gnome_helper"}
elif not host_ok:
    code="wrong_session"; nxt={"action":"start_gnome_wayland_session"}
elif not presentation_ok and winrects_active:
    code="presentation_degraded"; nxt={"action":"inspect_cua_gnome_helper"}
elif not worldline_ok:
    code="worldline_degraded"; nxt={"action":"restart_worldline"}
elif not observation_ok:
    code="observation_degraded"; nxt={"action":"rerun_installer","scope":"observation"}
else:
    code="cua_degraded"; nxt={"action":"inspect_cua_health"}

payload={
    "schema":"gwcu.diagnose.v3","ok":ready,"code":code,
    "host":{"session":session,"desktop":desktop,"ok":host_ok},
    "presentation":{"status":"ready" if presentation_ok else ("reload_required" if winrects_installed and not winrects_active else "degraded"),"exact_target_required":True,"winrects_installed":winrects_installed,"winrects_active":winrects_active,"response":presentation,"stderr":presentation_err[:1024] if presentation_err else None},
    "observation":{"status":"ready" if observation_ok else "degraded","pipewire":pw,"wireplumber":wp,"screencast_portal":screen,"screenshot_portal":screenshot,"gstreamer_pipewire":gst_pipewire,"gstreamer_png":gst_png,"observer_socket":observer},
    "worldline":{"status":"ready" if worldline_ok else "degraded","socket":worldline_socket,"response":worldline,"stderr":worldline_err[:1024] if worldline_err else None},
    "cua":{"status":cua_status,"binary":cua,"health":health,"doctor_exit":doctor_rc,"doctor":doctor,"winrects_installed":winrects_installed,"winrects_active":winrects_active},
    "next":nxt,
}
print(json.dumps(payload,separators=(",",":")))
raise SystemExit(0 if ready else 30)
PY
)
RC=$?
set -e

if $MACHINE; then
    printf '%s\n' "$OUTPUT"
else
    "$PYTHON" - "$OUTPUT" <<'PY'
import json,sys
d=json.loads(sys.argv[1])
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("  gnome-wayland-computer-use")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  Session:       {'READY' if d['host']['ok'] else 'DEGRADED'}  ({d['host']['session']} / {d['host']['desktop']})")
print(f"  Presentation:  {d['presentation']['status'].upper()}")
print(f"  Observation:   {d['observation']['status'].upper()}")
print(f"  WORLDLINE:     {d['worldline']['status'].upper()}")
print(f"  Cua control:   {d['cua']['status'].upper()}")
if d.get('next'): print(f"  Next:          {d['next']['action']}")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
PY
fi
exit "$RC"
