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
        set +e; identity_json=$("$IDENTITY" --resolve --machine "$TARGET" 2>/dev/null); identity_rc=$?; set -e
        [ -n "$identity_json" ] || identity_json='{"schema":"gwcu.identity.v1","ok":false,"code":"identity_unavailable","candidates":[],"next":{"action":"use_live_window_identity"}}'
        "$PYTHON" - "$TARGET" "$identity_json" "$identity_rc" "$host_json" "$cached_rc" <<'PY'
import json,sys
query=sys.argv[1]; ident=json.loads(sys.argv[2]); irc=int(sys.argv[3]); host=json.loads(sys.argv[4]); hrc=int(sys.argv[5])
host_view={"code":host.get("code","unknown"),"ok":bool(host.get("ok",False)),"cached":hrc==0}
code=ident.get("code","identity_unavailable")
base={"schema":"gwcu.route.v1","mode":"target","query":query,"host":host_view}
if irc==0 and ident.get("ok") and code=="resolved":
    base.update({"ok":True,"code":"target_resolved","identity":ident.get("result"),"evidence":ident.get("evidence",[]),
                 "next":{"action":"cua_target_state","query":query,"identity_source":"launcher"}})
    rc=0
elif code=="ambiguous":
    base.update({"ok":False,"code":"target_ambiguous","candidates":ident.get("candidates",[]),
                 "next":{"action":"disambiguate_target","query":query}})
    rc=10
else:
    # Launcher metadata is advisory. A missing desktop file does not mean a live
    # Cua target is missing, so hand the original user target directly to Cua.
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
