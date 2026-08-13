#!/usr/bin/env bash
# computer-use.sh — installed GWCU command/composition surface.
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
      Compact Cua, RemoteDesktop, observer and .gwcu status.

  /computer-use managed
      Enable managed repo/workspace-local .gwcu truths in the current scope.

  /computer-use managed on|off|status
      Change or inspect persistence. Enabling creates .gwcu; Git scopes also get /.gwcu in .gitignore.

  /computer-use truths
      Show the current .gwcu scope, path and stored truth counts.

  /computer-use consent
      Explain and verify the GNOME RemoteDesktop -> EIS/libei control path.

  /computer-use doctor
      Run the deterministic installed-system diagnosis.

  computer-use.sh span --actions-json '<json>'
      Execute an already-decided Cua action span behind one model/tool call.

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

run_action_span() {
    "$PYTHON" - "$@" <<'PY'
from __future__ import annotations
import argparse,json,os,pathlib,selectors,shutil,subprocess,sys,time

SCHEMA="gwcu.action-span.v1"
REQUEST_SCHEMA="gwcu.action-span.request.v1"
PROTOCOL="2024-11-05"
MAX_ACTIONS=64

def compact(v): return json.dumps(v,separators=(",",":"),ensure_ascii=True)
def envelope(ok,code,requested=0,completed=0,results=None,boundary=None,detail=None):
    out={"schema":SCHEMA,"ok":ok,"code":code,"requested":requested,"completed":completed,
         "results":results or [],"boundary":boundary}
    if detail: out["detail"]=detail
    return out

def resolve_driver(explicit):
    if explicit: return explicit
    env=os.environ.get("CUA_DRIVER_BIN")
    if env: return env
    found=shutil.which("cua-driver")
    if found: return found
    p=pathlib.Path.home()/".local/bin/cua-driver"
    return str(p) if p.is_file() and os.access(p,os.X_OK) else None

def send(proc,payload):
    proc.stdin.write(compact(payload)+"\n"); proc.stdin.flush()

def recv_for(proc,request_id,timeout):
    sel=selectors.DefaultSelector(); sel.register(proc.stdout,selectors.EVENT_READ)
    deadline=time.monotonic()+timeout
    try:
        while True:
            left=deadline-time.monotonic()
            if left<=0 or not sel.select(left): raise TimeoutError(f"timed out waiting for MCP response id={request_id}")
            line=proc.stdout.readline()
            if not line: raise RuntimeError("cua-driver MCP exited before responding")
            msg=json.loads(line)
            if msg.get("id")==request_id: return msg
    finally: sel.close()

def normalize(response):
    result=response.get("result")
    if not isinstance(result,dict): return result
    structured=result.get("structuredContent")
    if structured is None: structured=result.get("structured_content")
    return structured if structured is not None else result.get("content",result)

def boundary_reason(response):
    if "error" in response: return "mcp_error"
    result=response.get("result")
    if not isinstance(result,dict): return "invalid_result"
    if result.get("isError") is True: return "cua_error"
    structured=result.get("structuredContent")
    if structured is None: structured=result.get("structured_content")
    if isinstance(structured,dict):
        if structured.get("refused") is True: return "cua_refusal"
        if structured.get("ok") is False or structured.get("success") is False: return "cua_failure"
    return None

def parse_actions(raw):
    value=json.loads(raw)
    if isinstance(value,dict):
        if value.get("schema") not in (None,REQUEST_SCHEMA): raise ValueError("unsupported request schema")
        value=value.get("actions")
    if not isinstance(value,list) or not value: raise ValueError("actions must be a non-empty JSON array")
    if len(value)>MAX_ACTIONS: raise ValueError(f"action span exceeds {MAX_ACTIONS} actions")
    out=[]
    for i,a in enumerate(value):
        if not isinstance(a,dict): raise ValueError(f"action {i} must be an object")
        name=a.get("name"); arguments=a.get("arguments",{})
        if not isinstance(name,str) or not name.strip(): raise ValueError(f"action {i} requires a name")
        if not isinstance(arguments,dict): raise ValueError(f"action {i} arguments must be an object")
        out.append({"name":name,"arguments":arguments})
    return out

def execute(driver,actions,timeout):
    try:
        proc=subprocess.Popen([driver,"mcp"],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,
                              text=True,encoding="utf-8",errors="replace",bufsize=1)
    except OSError as exc:
        return envelope(False,"driver_unavailable",requested=len(actions),detail=str(exc)),50
    results=[]
    try:
        send(proc,{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":PROTOCOL,"capabilities":{},
             "clientInfo":{"name":"gwcu-action-span","version":"2.3.0"}}})
        init=recv_for(proc,1,timeout)
        if "error" in init or not isinstance(init.get("result"),dict):
            return envelope(False,"mcp_initialize_failed",requested=len(actions),detail=compact(init)),50
        send(proc,{"jsonrpc":"2.0","method":"notifications/initialized"})
        for index,action in enumerate(actions):
            rid=index+2
            send(proc,{"jsonrpc":"2.0","id":rid,"method":"tools/call",
                       "params":{"name":action["name"],"arguments":action["arguments"]}})
            response=recv_for(proc,rid,timeout)
            results.append({"index":index,"name":action["name"],"result":normalize(response)})
            reason=boundary_reason(response)
            if reason:
                return envelope(False,"boundary",requested=len(actions),completed=index,results=results,
                                boundary={"index":index,"name":action["name"],"reason":reason}),30
        return envelope(True,"completed",requested=len(actions),completed=len(actions),results=results),0
    except (TimeoutError,RuntimeError,ValueError,json.JSONDecodeError) as exc:
        return envelope(False,"transport_boundary",requested=len(actions),completed=len(results),results=results,detail=str(exc)),50
    finally:
        if proc.poll() is None:
            proc.terminate()
            try: proc.wait(timeout=1)
            except subprocess.TimeoutExpired:
                proc.kill(); proc.wait(timeout=1)

parser=argparse.ArgumentParser(description="Execute a predetermined Cua action span behind one model/tool boundary")
parser.add_argument("--driver")
parser.add_argument("--timeout",type=float,default=15.0)
parser.add_argument("--actions-json",required=True)
args=parser.parse_args(sys.argv[1:])
try: actions=parse_actions(args.actions_json)
except (ValueError,json.JSONDecodeError) as exc:
    print(compact(envelope(False,"invalid_request",detail=str(exc)))); raise SystemExit(2)
driver=resolve_driver(args.driver)
if not driver:
    print(compact(envelope(False,"driver_missing",requested=len(actions)))); raise SystemExit(50)
payload,rc=execute(driver,actions,max(1.0,min(args.timeout,120.0)))
print(compact(payload)); raise SystemExit(rc)
PY
}

command="${1:-help}"
[ "$#" -eq 0 ] || shift
case "$command" in
    span)
        # Hard invariant: this is ONE model/tool boundary for the whole already-decided span.
        # Cua remains the sole control authority; sequential Cua MCP calls stay inside this process.
        run_action_span "$@"
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
    print("A warm identity hit skips repeated launcher/PWA identity resolution.")
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
if c:
    print(f"  apps: {c.get('apps',0)}")
    print(f"  observed facts: {c.get('observed',0)}")
    print(f"  capabilities: {c.get('capabilities',0)}")
    print(f"  calibration: {c.get('calibration',0)}")
    print(f"  preferences: {c.get('preferences',0)}")
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
portal=p.get('portal',{}); token=portal.get('restore_token',{}); report=h.get('report') or {}; scope=m.get('scope') or {}
print("Computer use")
print(f"  Cua health: {report.get('overall') or h.get('code','unknown')}")
print(f"  RemoteDesktop portal: {'available' if portal.get('available') else 'unavailable'}")
print(f"  RemoteDesktop restore token: {'present' if token.get('present') else 'not established'}")
print(f"  managed .gwcu: {'on' if m.get('managed_truths') else 'off'}")
if scope.get('path'): print(f"  truth file: {scope['path']}")
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
