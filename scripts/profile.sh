#!/usr/bin/env bash
# profile.sh — cached session truth plus one-call routing/recovery composition.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIAGNOSE="${GWCU_DIAGNOSE_BIN:-$ROOT/scripts/diagnose.sh}"
IDENTITY="${GWCU_IDENTITY_BIN:-$ROOT/scripts/app-identity.sh}"
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use"
PROFILE="$STATE_DIR/profile.json"
QUIET=false
MACHINE=false
ACTION="${1:-read}"
[ "$#" -gt 0 ] && shift || true
ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --machine) MACHINE=true ;;
        --quiet) QUIET=true ;;
        --help|-h)
            echo "usage: $0 read|refresh|invalidate|route|recover [--machine] [--quiet] [target]"
            exit 0
            ;;
        --) shift; ARGS+=("$@"); break ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) ARGS+=("$1") ;;
    esac
    shift
done
[ -n "$PYTHON" ] || { echo "python3 is required" >&2; exit 30; }

read_profile() {
    [ -s "$PROFILE" ] || { printf '{"schema":"gwcu.profile.v2","ok":false,"code":"profile_missing","next":{"action":"refresh_profile"}}\n'; return 30; }
    "$PYTHON" - "$PROFILE" <<'PY'
import json,os,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
try: boot=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()
except OSError: boot=None
s=d.get("session",{}); cur=os.environ.get("XDG_SESSION_ID")
if d.get("schema")!="gwcu.profile.v2" or (boot and s.get("boot_id") and boot!=s["boot_id"]) or (cur and s.get("session_id") and cur!=s["session_id"]):
    print(json.dumps({"schema":"gwcu.profile.v2","ok":False,"code":"profile_stale","next":{"action":"refresh_profile"}},separators=(",",":")))
    raise SystemExit(30)
print(json.dumps(d,separators=(",",":")))
PY
}

refresh_profile() {
    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" 2>/dev/null || true
    local diag out rc
    diag=$(mktemp "$STATE_DIR/.diag.XXXXXX")
    out=$(mktemp "$STATE_DIR/.profile.XXXXXX")
    set +e; "$DIAGNOSE" --machine >"$diag"; rc=$?; set -e
    if [ ! -s "$diag" ]; then
        rm -f "$diag" "$out"
        printf '{"schema":"gwcu.profile.v2","ok":false,"code":"diagnose_failed","next":{"action":"diagnose"}}\n'
        return 50
    fi
    "$PYTHON" - "$diag" "$out" <<'PY'
import datetime,json,os,pathlib,sys
d=json.loads(pathlib.Path(sys.argv[1]).read_text())
try: boot=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()
except OSError: boot=None
p={"schema":"gwcu.profile.v2","ok":d.get("ok",False),"code":d.get("code","unknown"),
   "updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),
   "session":{"boot_id":boot,"session_id":os.environ.get("XDG_SESSION_ID")},
   "state":d,"next":d.get("next")}
out=pathlib.Path(sys.argv[2]); out.write_text(json.dumps(p,separators=(",",":"))+"\n"); os.chmod(out,0o600)
PY
    mv -f "$out" "$PROFILE"
    rm -f "$diag"
    cat "$PROFILE"
    return "$rc"
}

project_root() {
    case "${GWCU_PROJECT_MEMORY:-auto}" in 0|false|off|no) return 1 ;; esac
    if [ -n "${GWCU_PROJECT_ROOT:-}" ]; then
        [ -d "$GWCU_PROJECT_ROOT" ] || return 1
        (cd "$GWCU_PROJECT_ROOT" && pwd -P)
        return
    fi
    command -v git >/dev/null 2>&1 || return 1
    git -C "${GWCU_WORKDIR:-$PWD}" rev-parse --show-toplevel 2>/dev/null
}

project_memory() {
    local action="$1" target="$2" identity_json="${3:-}" root agents
    [ -n "$identity_json" ] || identity_json='{}'
    root=$(project_root 2>/dev/null || true)
    if [ -z "$root" ]; then
        printf '%s\n' '{"schema":"gwcu.project-memory.v1","ok":false,"code":"no_project","changed":false}'
        return 10
    fi
    agents="${GWCU_AGENTS_FILE:-$root/AGENTS.md}"
    "$PYTHON" - "$action" "$target" "$identity_json" "$agents" <<'PY'
import json,pathlib,re,sys

action,target,identity_raw,agents_raw=sys.argv[1:5]
path=pathlib.Path(agents_raw)
START='<!-- gwcu:desktop-truths:v1:start -->'
END='<!-- gwcu:desktop-truths:v1:end -->'
PREFIX='<!-- gwcu:app:v1 '
SUFFIX=' -->'
MAX=24

def compact(x):
    # AGENTS.md is agent context: keep learned values data-only inside HTML comments.
    return json.dumps(x,separators=(',',':'),sort_keys=True,ensure_ascii=True).replace('<','\\u003c').replace('>','\\u003e').replace('&','\\u0026')
def result(ok,code,**kw):
    print(compact({'schema':'gwcu.project-memory.v1','ok':ok,'code':code,'path':str(path),**kw}))
def norm(s): return re.sub(r'[^a-z0-9]+','-',str(s or '').casefold()).strip('-')
def load_text():
    try:return path.read_text(encoding='utf-8')
    except FileNotFoundError:return ''
    except OSError:return ''
def parse_entries(text):
    out=[]
    for line in text.splitlines():
        if line.startswith(PREFIX) and line.endswith(SUFFIX):
            try:
                d=json.loads(line[len(PREFIX):-len(SUFFIX)])
                if isinstance(d,dict) and d.get('key'): out.append(d)
            except Exception: pass
    return out

def matches(entry,q):
    qn=norm(q)
    vals=[entry.get('name'),entry.get('desktop_id'),entry.get('app_id'),entry.get('startup_wm_class'),entry.get('key')]
    for v in vals:
        if not v: continue
        raw=str(v).casefold()
        stem=raw[:-8] if raw.endswith('.desktop') else raw
        if q.casefold()==raw or q.casefold()==stem or (qn and qn in {norm(raw),norm(stem)}): return True
    return False

text=load_text(); entries=parse_entries(text)
if action=='lookup':
    hits=[e for e in entries if matches(e,target)]
    if len(hits)==1:
        result(True,'hit',changed=False,identity=hits[0]); raise SystemExit(0)
    if len(hits)>1:
        result(False,'ambiguous',changed=False,candidates=hits[:8]); raise SystemExit(10)
    result(False,'miss',changed=False); raise SystemExit(10)
if action!='remember':
    result(False,'bad_action',changed=False); raise SystemExit(2)
try: identity=json.loads(identity_raw)
except Exception:
    result(False,'invalid_identity',changed=False); raise SystemExit(10)
if not isinstance(identity,dict):
    result(False,'invalid_identity',changed=False); raise SystemExit(10)
entry={
    'key': identity.get('desktop_id') or identity.get('app_id') or norm(identity.get('display_name') or target),
    'name': identity.get('display_name') or target,
    'desktop_id': identity.get('desktop_id'),
    'app_id': identity.get('app_id'),
    'startup_wm_class': identity.get('startup_wm_class'),
    'kind': identity.get('kind'),
}
entry={k:v for k,v in entry.items() if v not in (None,'')}
if not entry.get('key'):
    result(False,'insufficient_identity',changed=False); raise SystemExit(10)
by_key={e.get('key'):e for e in entries}
old=by_key.get(entry['key'])
if old==entry:
    result(True,'unchanged',changed=False,identity=entry); raise SystemExit(0)
if old is None and len(by_key)>=MAX:
    result(False,'full',changed=False,limit=MAX); raise SystemExit(10)
by_key[entry['key']]=entry
rows=[by_key[k] for k in sorted(by_key,key=lambda x:str(x).casefold())]
block='\n'.join([
    START,
    '## GWCU desktop truths',
    'Stable local identities learned by computer-use routing. Live Cua state wins on contradiction.',
    *[PREFIX+compact(e)+SUFFIX for e in rows],
    END,
])
if START in text and END in text and text.index(START)<text.index(END):
    a=text.index(START); b=text.index(END,a)+len(END)
    new=text[:a]+block+text[b:]
else:
    base=text.rstrip()
    new=(base+'\n\n' if base else '')+block+'\n'
try:
    path.parent.mkdir(parents=True,exist_ok=True)
    tmp=path.with_name(path.name+'.gwcu.tmp')
    tmp.write_text(new,encoding='utf-8')
    tmp.replace(path)
except OSError as exc:
    result(False,'write_failed',changed=False,detail=str(exc)); raise SystemExit(10)
result(True,'recorded',changed=True,identity=entry)
PY
}

case "$ACTION" in
    invalidate)
        rm -f "$PROFILE"
        $QUIET || printf '{"schema":"gwcu.profile.v2","ok":true,"code":"invalidated","next":null}\n'
        ;;
    refresh)
        if $QUIET; then refresh_profile >/dev/null; else refresh_profile; fi
        ;;
    read)
        read_profile
        ;;
    route)
        [ "${#ARGS[@]}" -gt 0 ] || { echo "route requires a target" >&2; exit 2; }
        TARGET="${ARGS[*]}"
        host_json='{"schema":"gwcu.profile.v2","ok":false,"code":"profile_unavailable","next":null}'
        set +e; cached=$(read_profile 2>/dev/null); cached_rc=$?; set -e
        [ -n "${cached:-}" ] && host_json="$cached"

        set +e; memory_json=$(project_memory lookup "$TARGET" '{}' 2>/dev/null); memory_rc=$?; set -e
        [ -n "${memory_json:-}" ] || memory_json='{"schema":"gwcu.project-memory.v1","ok":false,"code":"unavailable","changed":false}'
        if [ "$memory_rc" -eq 0 ]; then
            "$PYTHON" - "$TARGET" "$memory_json" "$host_json" "$cached_rc" <<'PY'
import json,sys
query=sys.argv[1]; mem=json.loads(sys.argv[2]); host=json.loads(sys.argv[3]); hrc=int(sys.argv[4])
host_view={'code':host.get('code','unknown'),'ok':bool(host.get('ok',False)),'cached':hrc==0}
p={'schema':'gwcu.route.v1','mode':'target','query':query,'host':host_view,'ok':True,'code':'target_resolved',
   'identity':mem.get('identity'),'evidence':['project_agents_truth'],'project_memory':{'code':mem.get('code'),'path':mem.get('path'),'changed':False},
   'next':{'action':'cua_target_state','query':query,'identity_source':'project_agents'}}
print(json.dumps(p,separators=(',',':')))
PY
            exit 0
        fi

        set +e; identity_json=$("$IDENTITY" --resolve --machine "$TARGET" 2>/dev/null); identity_rc=$?; set -e
        [ -n "$identity_json" ] || identity_json='{"schema":"gwcu.identity.v1","ok":false,"code":"identity_unavailable","candidates":[],"next":{"action":"use_live_window_identity"}}'
        remembered='{"schema":"gwcu.project-memory.v1","ok":false,"code":"not_recorded","changed":false}'
        if [ "$identity_rc" -eq 0 ]; then
            set +e
            identity_result=$("$PYTHON" - "$identity_json" <<'PY'
import json,sys
print(json.dumps(json.loads(sys.argv[1]).get('result') or {},separators=(',',':')))
PY
)
            remembered=$(project_memory remember "$TARGET" "$identity_result" 2>/dev/null)
            set -e
            [ -n "${remembered:-}" ] || remembered='{"schema":"gwcu.project-memory.v1","ok":false,"code":"not_recorded","changed":false}'
        fi
        "$PYTHON" - "$TARGET" "$identity_json" "$identity_rc" "$host_json" "$cached_rc" "$remembered" <<'PY'
import json,sys
query=sys.argv[1]; ident=json.loads(sys.argv[2]); irc=int(sys.argv[3]); host=json.loads(sys.argv[4]); hrc=int(sys.argv[5]); mem=json.loads(sys.argv[6])
host_view={"code":host.get("code","unknown"),"ok":bool(host.get("ok",False)),"cached":hrc==0}
mem_view={k:mem.get(k) for k in ('code','path','changed') if mem.get(k) is not None}
code=ident.get("code","identity_unavailable")
base={"schema":"gwcu.route.v1","mode":"target","query":query,"host":host_view,"project_memory":mem_view}
if irc==0 and ident.get("ok") and code=="resolved":
    base.update({"ok":True,"code":"target_resolved","identity":ident.get("result"),"evidence":ident.get("evidence",[]),
                 "next":{"action":"cua_target_state","query":query,"identity_source":"launcher"}})
    rc=0
elif code=="ambiguous":
    base.update({"ok":False,"code":"target_ambiguous","candidates":ident.get("candidates",[]),
                 "next":{"action":"disambiguate_target","query":query}})
    rc=10
else:
    base.update({"ok":True,"code":"live_target","identity":None,
                 "next":{"action":"cua_target_state","query":query,"identity_source":"live"}})
    rc=0
print(json.dumps(base,separators=(",",":")))
raise SystemExit(rc)
PY
        ;;
    recover)
        set +e; current=$(read_profile 2>/dev/null); rc=$?; set -e
        source=cached
        if [ "$rc" -ne 0 ] || [ -z "$current" ]; then
            source=refreshed
            set +e; current=$(refresh_profile 2>/dev/null); rc=$?; set -e
        fi
        [ -n "$current" ] || current='{"schema":"gwcu.profile.v2","ok":false,"code":"profile_unavailable","next":{"action":"diagnose"}}'
        "$PYTHON" - "$current" "$source" <<'PY'
import json,sys
d=json.loads(sys.argv[1]); source=sys.argv[2]
ok=bool(d.get("ok",False))
p={"schema":"gwcu.route.v1","mode":"recovery","ok":ok,
   "code":"host_ready" if ok else "host_recovery","source":source,
   "profile":{"code":d.get("code","unknown"),"updated_at":d.get("updated_at")},
   "next":None if ok else d.get("next")}
print(json.dumps(p,separators=(",",":")))
raise SystemExit(0 if ok else 30)
PY
        ;;
    *)
        echo "usage: $0 read|refresh|invalidate|route|recover [--machine] [--quiet] [target]" >&2
        exit 2
        ;;
esac
