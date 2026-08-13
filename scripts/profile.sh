#!/usr/bin/env bash
# profile.sh — passive session state; never a task preflight.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIAGNOSE="$ROOT/scripts/diagnose.sh"
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use"
PROFILE="$STATE_DIR/profile.json"
QUIET=false
ACTION="${1:-read}"; [ "$#" -gt 0 ] && shift || true
while [ "$#" -gt 0 ]; do
    case "$1" in --machine) ;; --quiet) QUIET=true ;; --help|-h) echo "usage: $0 read|refresh|invalidate [--machine] [--quiet]"; exit 0 ;; *) exit 2 ;; esac
    shift
done
[ -n "$PYTHON" ] || { echo "python3 is required" >&2; exit 30; }
case "$ACTION" in
    invalidate)
        rm -f "$PROFILE"; $QUIET || printf '{"schema":"gwcu.profile.v2","ok":true,"code":"invalidated","next":null}\n';;
    refresh)
        mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" 2>/dev/null || true
        diag=$(mktemp "$STATE_DIR/.diag.XXXXXX"); out=$(mktemp "$STATE_DIR/.profile.XXXXXX")
        trap 'rm -f "$diag" "$out"' EXIT
        set +e; "$DIAGNOSE" --machine >"$diag"; rc=$?; set -e
        [ -s "$diag" ] || { $QUIET || printf '{"schema":"gwcu.profile.v2","ok":false,"code":"diagnose_failed","next":{"action":"diagnose"}}\n'; exit 50; }
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
        mv -f "$out" "$PROFILE"; trap - EXIT; rm -f "$diag"; $QUIET || cat "$PROFILE"; exit "$rc";;
    read)
        [ -s "$PROFILE" ] || { printf '{"schema":"gwcu.profile.v2","ok":false,"code":"profile_missing","next":{"action":"refresh_profile"}}\n'; exit 30; }
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
        ;;
    *) echo "usage: $0 read|refresh|invalidate [--machine] [--quiet]" >&2; exit 2 ;;
esac
