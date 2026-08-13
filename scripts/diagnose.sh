#!/usr/bin/env bash
# diagnose.sh — one compact verdict: observation + upstream Cua.
set -euo pipefail
MACHINE=false
for arg in "$@"; do
    case "$arg" in
        --machine|--json) MACHINE=true ;;
        --help|-h) echo "usage: $0 [--machine|--json]"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
[ -n "$PYTHON" ] || { echo "python3 is required" >&2; exit 30; }

set +e
OUTPUT=$(
"$PYTHON" - <<'PY'
import json, os, pathlib, shutil, subprocess

def run(argv, timeout=4):
    try:
        p=subprocess.run(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,timeout=timeout)
        return p.returncode,p.stdout.strip(),p.stderr.strip()
    except (OSError,subprocess.TimeoutExpired) as e:
        return 127,"",str(e)

def portal(name):
    if not shutil.which("gdbus"): return False
    rc,out,_=run(["gdbus","introspect","--session","--dest","org.freedesktop.portal.Desktop","--object-path","/org/freedesktop/portal/desktop"])
    return rc==0 and f"interface org.freedesktop.portal.{name}" in out

def active_unit(name):
    if not shutil.which("systemctl"): return False
    rc,_,_=run(["systemctl","--user","is-active","--quiet",name])
    return rc==0

def extension_active(uuid):
    if not shutil.which("gnome-extensions"): return False
    rc,out,_=run(["gnome-extensions","info",uuid])
    return rc==0 and "State:" in out and "ACTIVE" in out

session=os.environ.get("XDG_SESSION_TYPE") or "unknown"
desktop=os.environ.get("XDG_CURRENT_DESKTOP") or "unknown"
host_ok=session=="wayland" and "GNOME" in desktop

pw=run(["pw-cli","info","0"])[0]==0 if shutil.which("pw-cli") else False
wp=active_unit("wireplumber.service")
gst_pipewire=run(["gst-inspect-1.0","pipewiresrc"])[0]==0 if shutil.which("gst-inspect-1.0") else False
gst_png=run(["gst-inspect-1.0","pngenc"])[0]==0 if shutil.which("gst-inspect-1.0") else False
screen=portal("ScreenCast")
screenshot=portal("Screenshot")
observer=active_unit("gnome-wayland-computer-use-observer.socket")
observation_ok=all((pw,wp,gst_pipewire,gst_png,screen,observer))

cua=shutil.which("cua-driver")
if not cua:
    candidate=pathlib.Path.home()/".local/bin/cua-driver"
    if candidate.is_file() and os.access(candidate,os.X_OK): cua=str(candidate)

doctor_rc=127; doctor=None
if cua:
    doctor_rc,out,err=run([cua,"doctor","--json"],timeout=12)
    if out:
        try: doctor=json.loads(out)
        except Exception: doctor={"raw":out[:4096]}

winrects_dir=pathlib.Path(os.environ.get("XDG_DATA_HOME",str(pathlib.Path.home()/".local/share")))/"gnome-shell/extensions/winrects@cua"
winrects_installed=winrects_dir.is_dir()
winrects_active=extension_active("winrects@cua")
if not winrects_active and winrects_installed and host_ok:
    cua_status="reload_required"
elif cua and doctor_rc==0 and winrects_active:
    cua_status="ready"
else:
    cua_status="degraded"

ready=host_ok and observation_ok and cua_status=="ready"
if ready:
    code="ready"; nxt=None
elif cua_status=="reload_required" and observation_ok:
    code="reload_required"; nxt={"action":"logout_login","reason":"activate_cua_gnome_helper"}
elif not host_ok:
    code="wrong_session"; nxt={"action":"start_gnome_wayland_session"}
elif not observation_ok:
    code="observation_degraded"; nxt={"action":"rerun_installer","scope":"observation"}
else:
    code="cua_degraded"; nxt={"action":"run_cua_doctor"}

payload={
    "schema":"gwcu.diagnose.v2",
    "ok":ready,
    "code":code,
    "host":{"session":session,"desktop":desktop,"ok":host_ok},
    "observation":{
        "status":"ready" if observation_ok else "degraded",
        "pipewire":pw,"wireplumber":wp,"screencast_portal":screen,
        "screenshot_portal":screenshot,"gstreamer_pipewire":gst_pipewire,
        "gstreamer_png":gst_png,"observer_socket":observer,
    },
    "cua":{
        "status":cua_status,"binary":cua,"doctor_exit":doctor_rc,
        "winrects_installed":winrects_installed,"winrects_active":winrects_active,
        "doctor":doctor,
    },
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
print(f"  Session:      {'READY' if d['host']['ok'] else 'DEGRADED'}  ({d['host']['session']} / {d['host']['desktop']})")
print(f"  Observation:  {d['observation']['status'].upper()}")
print(f"  Cua control:  {d['cua']['status'].upper()}")
if d.get('next'): print(f"  Next:         {d['next']['action']}")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
PY
fi
exit "$RC"
