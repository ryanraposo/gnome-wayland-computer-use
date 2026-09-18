#!/usr/bin/env bash
# profile.sh — cached session truth plus one-call routing/recovery composition.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIAGNOSE="${GWCU_DIAGNOSE_BIN:-$ROOT/scripts/diagnose.sh}"
IDENTITY="${GWCU_IDENTITY_BIN:-$ROOT/scripts/app-identity.sh}"
TRUTHS="${GWCU_TRUTHS_BIN:-$ROOT/scripts/truths.py}"
PYTHON="${GWCU_SYSTEM_PYTHON:-${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use"
PROFILE="$STATE_DIR/profile.json"
MANAGED_PREF="$STATE_DIR/managed-truths"
LEGACY_MANAGED_PREF="$STATE_DIR/managed-agents"
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
            echo "usage: $0 read|refresh|invalidate|route|recover|managed|truths [--machine] [--quiet] [args]"
            exit 0
            ;;
        --) shift; ARGS+=("$@"); break ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) ARGS+=("$1") ;;
    esac
    shift
done
[ -n "$PYTHON" ] || { echo "python3 is required" >&2; exit 30; }
[ -f "$TRUTHS" ] || { echo "GWCU truth helper is missing: $TRUTHS" >&2; exit 30; }

managed_default() {
    local pref file="$MANAGED_PREF"
    [ -s "$file" ] || file="$LEGACY_MANAGED_PREF"
    if [ -s "$file" ]; then
        IFS= read -r pref <"$file" || true
        case "${pref,,}" in
            on|yes|true|1) printf 'on\n'; return ;;
            off|no|false|0) printf 'off\n'; return ;;
        esac
    fi
    printf 'on\n'
}

truths_enabled() {
    local v pref
    if [ "${GWCU_TRUTHS+x}" = x ]; then
        v="${GWCU_TRUTHS,,}"
        case "$v" in 0|false|off|no) return 1 ;; *) return 0 ;; esac
    fi
    # Backward-compatible runtime override from the pre-.gwcu PR shape.
    if [ "${GWCU_PROJECT_MEMORY+x}" = x ]; then
        v="${GWCU_PROJECT_MEMORY,,}"
        case "$v" in 0|false|off|no) return 1 ;; *) return 0 ;; esac
    fi
    pref=$(managed_default)
    [ "$pref" = on ]
}

write_managed_preference() {
    local value="$1" tmp
    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" 2>/dev/null || true
    tmp=$(mktemp "$STATE_DIR/.managed-truths.XXXXXX")
    printf '%s\n' "$value" >"$tmp"
    chmod 600 "$tmp"
    mv -f "$tmp" "$MANAGED_PREF"
    rm -f "$LEGACY_MANAGED_PREF"
}

truth_status_json() {
    set +e
    local out
    out=$("$PYTHON" "$TRUTHS" status 2>/dev/null)
    set -e
    [ -n "$out" ] && printf '%s\n' "$out" || printf '%s\n' '{"schema":"gwcu.truths.v1","ok":false,"code":"unavailable"}'
}

managed_result() {
    local value source scope
    value=$(managed_default)
    if [ "${GWCU_TRUTHS+x}" = x ] || [ "${GWCU_PROJECT_MEMORY+x}" = x ]; then
        source=environment
        if truths_enabled; then value=on; else value=off; fi
    elif [ -s "$MANAGED_PREF" ]; then
        source=installer
    elif [ -s "$LEGACY_MANAGED_PREF" ]; then
        source=legacy_installer
    else
        source=default
    fi
    scope=$(truth_status_json)
    "$PYTHON" - "$value" "$source" "$MANAGED_PREF" "$scope" <<'PY'
import json,sys
value,source,path,scope_raw=sys.argv[1:5]
try: scope=json.loads(scope_raw)
except Exception: scope={"schema":"gwcu.truths.v1","ok":False,"code":"unavailable"}
print(json.dumps({
    "schema":"gwcu.preferences.v1","ok":True,"code":f"managed_truths_{value}",
    "managed_truths":value=="on","source":source,"path":path,"scope":scope,
    "max_repeat_identity_resolution_savings_percent":100,
},separators=(",",":")))
PY
}

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

sync_existing_truths() {
    truths_enabled || return 0
    local status generated
    set +e; status=$("$PYTHON" "$TRUTHS" status 2>/dev/null); local status_rc=$?; set -e
    [ "$status_rc" -eq 0 ] || return 0
    generated=$("$PYTHON" - "$PROFILE" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text())
s=p.get('state') or {}; host=s.get('host') or {}; obs=s.get('observation') or {}; cua=s.get('cua') or {}
print(json.dumps({
  'observed': {k:v for k,v in {'session_type':host.get('session'),'desktop':host.get('desktop')}.items() if v not in (None,'unknown','')},
  'capabilities': {
    'gnome_wayland': bool(host.get('ok')),
    'whole_screen': obs.get('status')=='ready',
    'cua_control': cua.get('status')=='ready',
  }
},separators=(',',':')))
PY
)
    "$PYTHON" - "$generated" "$TRUTHS" <<'PY' >/dev/null 2>&1 || true
import json,subprocess,sys
value=json.loads(sys.argv[1]); tool=sys.argv[2]
for section in ('observed','capabilities'):
    subprocess.run([sys.executable,tool,'merge','--section',section,'--json',json.dumps(value[section],separators=(',',':'))],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,check=False)
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
    sync_existing_truths
    cat "$PROFILE"
    return "$rc"
}

truth_lookup() {
    local target="$1"
    if ! truths_enabled; then
        printf '%s\n' '{"schema":"gwcu.truths.v1","ok":false,"code":"disabled","changed":false}'
        return 10
    fi
    "$PYTHON" "$TRUTHS" lookup --target "$target"
}

truth_remember() {
    local target="$1" identity_json="$2"
    if ! truths_enabled; then
        printf '%s\n' '{"schema":"gwcu.truths.v1","ok":false,"code":"disabled","changed":false}'
        return 10
    fi
    "$PYTHON" "$TRUTHS" remember --target "$target" --identity-json "$identity_json"
}

case "$ACTION" in
    managed)
        sub="${ARGS[0]:-status}"
        case "${sub,,}" in
            on|yes|true|1)
                write_managed_preference on
                "$PYTHON" "$TRUTHS" init >/dev/null
                ;;
            off|no|false|0)
                write_managed_preference off
                ;;
            status) ;;
            *) echo "managed expects on|off|status" >&2; exit 2 ;;
        esac
        managed_result
        ;;
    truths)
        sub="${ARGS[0]:-status}"
        case "$sub" in
            status|scope|init|regenerate)
                "$PYTHON" "$TRUTHS" "$sub"
                ;;
            *) echo "truths expects status|scope|init|regenerate" >&2; exit 2 ;;
        esac
        ;;
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

        set +e; memory_json=$(truth_lookup "$TARGET" 2>/dev/null); memory_rc=$?; set -e
        [ -n "${memory_json:-}" ] || memory_json='{"schema":"gwcu.truths.v1","ok":false,"code":"unavailable","changed":false}'
        if [ "$memory_rc" -eq 0 ]; then
            "$PYTHON" - "$TARGET" "$memory_json" "$host_json" "$cached_rc" <<'PY'
import json,sys
query=sys.argv[1]; mem=json.loads(sys.argv[2]); host=json.loads(sys.argv[3]); hrc=int(sys.argv[4])
host_view={'code':host.get('code','unknown'),'ok':bool(host.get('ok',False)),'cached':hrc==0}
p={'schema':'gwcu.route.v1','mode':'target','query':query,'host':host_view,'ok':True,'code':'target_resolved',
   'identity':mem.get('identity'),'evidence':['gwcu_truth'],'truths':{k:mem.get(k) for k in ('code','path','root','source','changed') if mem.get(k) is not None},
   'next':{'action':'cua_target_state','query':query,'identity_source':'gwcu'}}
print(json.dumps(p,separators=(',',':')))
PY
            exit 0
        fi

        set +e; identity_json=$("$IDENTITY" --resolve --machine "$TARGET" 2>/dev/null); identity_rc=$?; set -e
        [ -n "$identity_json" ] || identity_json='{"schema":"gwcu.identity.v1","ok":false,"code":"identity_unavailable","candidates":[],"next":{"action":"use_live_window_identity"}}'
        remembered='{"schema":"gwcu.truths.v1","ok":false,"code":"not_recorded","changed":false}'
        if [ "$identity_rc" -eq 0 ]; then
            set +e
            identity_result=$("$PYTHON" - "$identity_json" <<'PY'
import json,sys
print(json.dumps(json.loads(sys.argv[1]).get('result') or {},separators=(',',':')))
PY
)
            remembered=$(truth_remember "$TARGET" "$identity_result" 2>/dev/null)
            set -e
            [ -n "${remembered:-}" ] || remembered='{"schema":"gwcu.truths.v1","ok":false,"code":"not_recorded","changed":false}'
        fi
        "$PYTHON" - "$TARGET" "$identity_json" "$identity_rc" "$host_json" "$cached_rc" "$remembered" <<'PY'
import json,sys
query=sys.argv[1]; ident=json.loads(sys.argv[2]); irc=int(sys.argv[3]); host=json.loads(sys.argv[4]); hrc=int(sys.argv[5]); mem=json.loads(sys.argv[6])
host_view={"code":host.get("code","unknown"),"ok":bool(host.get("ok",False)),"cached":hrc==0}
mem_view={k:mem.get(k) for k in ('code','path','root','source','gitignore','changed') if mem.get(k) is not None}
code=ident.get("code","identity_unavailable")
base={"schema":"gwcu.route.v1","mode":"target","query":query,"host":host_view,"truths":mem_view}
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
        echo "usage: $0 read|refresh|invalidate|route|recover|managed|truths [--machine] [--quiet] [args]" >&2
        exit 2
        ;;
esac
