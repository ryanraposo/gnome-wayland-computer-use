#!/usr/bin/env bash
# diagnose.sh — one compact verdict: desktop env + presentation + observation + WORLDLINE + Cua identity.
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
SESSION_ENV="$ROOT/scripts/session-environment.py"

set +e
OUTPUT=$(
"$PYTHON" - "$HEALTH" "$WORLDLINE" "$PRESENTER" "$SESSION_ENV" <<'PY'
import json, os, pathlib, re, shutil, subprocess, sys
health_script,worldline_script,presenter_script,session_env_script=sys.argv[1:5]
SEMVER=re.compile(r"\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b")
ENV_KEYS=("DISPLAY","WAYLAND_DISPLAY","XDG_SESSION_TYPE","XDG_CURRENT_DESKTOP","XDG_RUNTIME_DIR")

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

def parsed_json(out, fallback=None):
    try:return json.loads(out) if out else fallback
    except Exception:return fallback

def real(path):
    return os.path.realpath(path) if isinstance(path,str) and path else None

def version_from_text(text):
    m=SEMVER.search(str(text or ""));return m.group(1) if m else None

def doctor_version(doc):
    if not isinstance(doc,dict):return None
    checks=doc.get("checks") or []
    if isinstance(checks,list):
        for entry in checks:
            if isinstance(entry,dict) and entry.get("name")=="binary_version":
                for key in ("message","detail","summary"):
                    if v:=version_from_text(entry.get(key)):return v
    # Some cua-driver CLI builds nest the stable health payload.
    for key in ("report","health_report","structuredContent","structured_content"):
        if isinstance(doc.get(key),dict):
            if v:=doctor_version(doc[key]):return v
    return None

def same_identity(a,b):
    return bool(a and b and real(a.get("binary"))==real(b.get("binary")) and a.get("version") and a.get("version")==b.get("version"))

# Shell/systemd/running-gateway desktop environment proof.
env_rc,env_out,env_err=run([sys.executable,session_env_script,"snapshot"],8)
env_proof=parsed_json(env_out,{"ok":False,"code":"invalid_output","gateways":[]}) or {}
shell_env=((env_proof.get("shell") or {}).get("values") or {})
session=shell_env.get("XDG_SESSION_TYPE") or os.environ.get("XDG_SESSION_TYPE") or "unknown"
desktop=shell_env.get("XDG_CURRENT_DESKTOP") or os.environ.get("XDG_CURRENT_DESKTOP") or "unknown"
host_ok=session=="wayland" and "GNOME" in desktop and bool((env_proof.get("shell") or {}).get("valid"))
environment_ok=env_rc==0 and bool(env_proof.get("ok"))
gateways=env_proof.get("gateways") if isinstance(env_proof.get("gateways"),list) else []

pipewire_service=active_unit("pipewire.service")
pipewire_rpc=run(["pw-cli","info","0"],3)[0]==0 if shutil.which("pw-cli") else False
pw=pipewire_service and pipewire_rpc
wp=active_unit("wireplumber.service")
gst_pipewire=run(["gst-inspect-1.0","pipewiresrc"],3)[0]==0 if shutil.which("gst-inspect-1.0") else False
gst_png=run(["gst-inspect-1.0","pngenc"],3)[0]==0 if shutil.which("gst-inspect-1.0") else False
screen=portal("ScreenCast"); screenshot=portal("Screenshot")
observer=active_unit("gnome-wayland-computer-use-observer.socket")
observation_ok=all((pw,wp,gst_pipewire,gst_png,screen,observer))
failing_observation_services=[]
if not pw:failing_observation_services.append("pipewire.service")
if not wp:failing_observation_services.append("wireplumber.service")

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
cua=real(cua)
health=None; health_rc=50; doctor=None; doctor_rc=127
if cua:
    health_rc,out,_=run([sys.executable,health_script,"--driver",cua],20)
    if out:
        try: health=json.loads(out)
        except Exception: health={"schema":"gwcu.cua-health.v2","ok":False,"code":"invalid_output","detail":out[:4096]}
    doctor_rc,out,_=run([cua,"doctor","--json"],15)
    if out:
        try: doctor=json.loads(out)
        except Exception: doctor={"raw":out[:4096]}

health_code=(health or {}).get("code","unavailable")
installed_identity={"binary":cua,"version":(health or {}).get("executable_version")}
doctor_identity={"binary":cua,"version":doctor_version(doctor) or (health or {}).get("reported_version")}
gateway_identity_rows=[]
identity_ok=bool((health or {}).get("identity_ok")) and same_identity(installed_identity,doctor_identity)
for gateway in gateways:
    selected=gateway.get("hermes_selected") if isinstance(gateway.get("hermes_selected"),dict) else {}
    backend=gateway.get("gateway_backend") if isinstance(gateway.get("gateway_backend"),dict) else {}
    selected={"binary":real(selected.get("binary")),"version":selected.get("version")}
    backend={"binary":real(backend.get("binary")),"version":backend.get("version")}
    row={
        "pid":gateway.get("pid"),"hermes_home":gateway.get("hermes_home"),
        "hermes_selected":selected,"gateway_backend":backend,
        "environment_ok":bool(gateway.get("environment_attestation_ok")),
    }
    row["matches_installed"]=same_identity(installed_identity,selected) and same_identity(installed_identity,backend)
    gateway_identity_rows.append(row)
    identity_ok=identity_ok and row["matches_installed"] and row["environment_ok"]

if winrects_installed and not winrects_active and host_ok:
    cua_status="reload_required"
elif health_rc==0 and winrects_active and identity_ok:
    cua_status="ready"
elif health_code in {"failed","identity_split_brain"} or not identity_ok:
    cua_status="failed"
else:
    cua_status="degraded"

ready=host_ok and environment_ok and observation_ok and worldline_ok and presentation_ok and cua_status=="ready" and identity_ok
if ready:
    code="ready"; nxt=None
elif not identity_ok:
    code="cua_identity_split_brain"; nxt={"action":"repair_cua_identity","reason":"installed_hermes_gateway_doctor_must_match"}
elif not environment_ok:
    code="desktop_environment_unproved"; nxt={"action":"sync_desktop_environment","reason":"shell_systemd_gateway_must_match"}
elif cua_status=="reload_required" and observation_ok and worldline_ok:
    code="reload_required"; nxt={"action":"logout_login","reason":"activate_cua_gnome_helper"}
elif not host_ok:
    code="wrong_session"; nxt={"action":"start_gnome_wayland_session"}
elif not presentation_ok and winrects_active:
    code="presentation_degraded"; nxt={"action":"inspect_cua_gnome_helper"}
elif not worldline_ok:
    code="worldline_degraded"; nxt={"action":"restart_worldline"}
elif failing_observation_services:
    code="observation_degraded"; nxt={"action":"restart_services","services":failing_observation_services}
elif not observation_ok:
    code="observation_degraded"; nxt={"action":"repair_observation_components","components":[k for k,v in {"screencast_portal":screen,"gstreamer_pipewire":gst_pipewire,"gstreamer_png":gst_png,"observer_socket":observer}.items() if not v]}
else:
    code="cua_degraded"; nxt={"action":"inspect_cua_health"}

payload={
    "schema":"gwcu.diagnose.v4","ok":ready,"code":code,
    "host":{"session":session,"desktop":desktop,"ok":host_ok},
    "desktop_environment":env_proof,
    "presentation":{"status":"ready" if presentation_ok else ("reload_required" if winrects_installed and not winrects_active else "degraded"),"exact_target_required":True,"winrects_installed":winrects_installed,"winrects_active":winrects_active,"response":presentation,"stderr":presentation_err[:1024] if presentation_err else None},
    "observation":{"status":"ready" if observation_ok else "degraded","pipewire":pw,"pipewire_service":pipewire_service,"pipewire_rpc":pipewire_rpc,"wireplumber":wp,"screencast_portal":screen,"screenshot_portal":screenshot,"gstreamer_pipewire":gst_pipewire,"gstreamer_png":gst_png,"observer_socket":observer,"failing_services":failing_observation_services},
    "worldline":{"status":"ready" if worldline_ok else "degraded","socket":worldline_socket,"response":worldline,"stderr":worldline_err[:1024] if worldline_err else None},
    "cua":{"status":cua_status,"binary":cua,"health":health,"doctor_exit":doctor_rc,"doctor":doctor,"winrects_installed":winrects_installed,"winrects_active":winrects_active,"identity":{"ok":identity_ok,"installed":installed_identity,"doctor_reported":doctor_identity,"gateways":gateway_identity_rows,"invariant":"installed == hermes_selected == gateway_backend == doctor_reported"}},
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
d=json.loads(sys.argv[1]); env=d.get('desktop_environment') or {}; shell=(env.get('shell') or {}).get('values') or {}; systemd=(env.get('systemd') or {}).get('values') or {}; gateways=env.get('gateways') or []; ident=(d.get('cua') or {}).get('identity') or {}
def wd(v):return v.get('WAYLAND_DISPLAY') or '-'
def iv(v):
 if not isinstance(v,dict):return '-'
 b=v.get('binary') or '-'; ver=v.get('version') or '?';return f"{b} @ {ver}"
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print("  gnome-wayland-computer-use")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"  Session:       {'READY' if d['host']['ok'] else 'DEGRADED'}  ({d['host']['session']} / {d['host']['desktop']})")
print(f"  Wayland shell: {wd(shell)}")
print(f"  Wayland systemd:{wd(systemd)}")
if gateways:
 for g in gateways: print(f"  Wayland gateway[{g.get('pid')}]: {wd(g.get('environment') or {})}")
else: print("  Wayland gateway: no running Hermes gateway attestation")
print(f"  Presentation:  {d['presentation']['status'].upper()}")
print(f"  Observation:   {d['observation']['status'].upper()}")
print(f"  WORLDLINE:     {d['worldline']['status'].upper()}")
print(f"  Cua control:   {d['cua']['status'].upper()}")
print(f"  Cua installed: {iv(ident.get('installed'))}")
for g in ident.get('gateways') or []:
 print(f"  Cua Hermes[{g.get('pid')}]: {iv(g.get('hermes_selected'))}")
 print(f"  Cua backend[{g.get('pid')}]: {iv(g.get('gateway_backend'))}")
print(f"  Cua doctor:    {iv(ident.get('doctor_reported'))}")
print(f"  Cua identity:  {'PASS' if ident.get('ok') else 'FAIL'}")
if d.get('next'):
 nxt=d['next']; detail=', '.join(nxt.get('services') or [])
 print(f"  Next:          {nxt['action']}{' ('+detail+')' if detail else ''}")
print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
PY
fi
exit "$RC"
