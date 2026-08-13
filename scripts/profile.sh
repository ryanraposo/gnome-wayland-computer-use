#!/usr/bin/env bash
# profile.sh — passive capability state for failure recovery, never a task preflight.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIAGNOSE="$ROOT/scripts/diagnose.sh"
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use"
PROFILE="$STATE_DIR/profile.json"
QUIET=false; MACHINE=false
usage(){ echo "usage: $0 read|refresh|invalidate [--machine] [--quiet]" >&2; }
ACTION="${1:-read}"; [ "$#" -gt 0 ] && shift || true
while [ "$#" -gt 0 ]; do case "$1" in --machine) MACHINE=true;; --quiet) QUIET=true;; --help|-h) usage; exit 0;; *) usage; exit 2;; esac; shift; done
[ -n "$PYTHON" ] || { echo "python3 is required" >&2; exit 30; }
case "$ACTION" in
invalidate)
    rm -f "$PROFILE"; $QUIET || printf '{"schema":"gwcu.profile.v1","ok":true,"code":"invalidated","next":null}\n'; exit 0;;
refresh)
    mkdir -p "$STATE_DIR"; chmod 700 "$STATE_DIR" 2>/dev/null || true
    tmp_diag=$(mktemp "$STATE_DIR/.diagnose.XXXXXX"); tmp_profile=$(mktemp "$STATE_DIR/.profile.XXXXXX")
    trap 'rm -f "$tmp_diag" "$tmp_profile"' EXIT
    "$DIAGNOSE" --machine >"$tmp_diag" || { $QUIET || printf '{"schema":"gwcu.profile.v1","ok":false,"code":"diagnose_failed","retryable":true,"terminal":false,"next":{"action":"diagnose"}}\n'; exit 50; }
    "$PYTHON" - "$tmp_diag" "$tmp_profile" <<'PY'
import datetime,json,os,pathlib,sys
diag=json.loads(pathlib.Path(sys.argv[1]).read_text())
try: boot=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()
except OSError: boot=None
p={"schema":"gwcu.profile.v1","ok":True,"code":"ok","updated_at":datetime.datetime.now(datetime.timezone.utc).isoformat(),"session":{"boot_id":boot,"session_id":os.environ.get("XDG_SESSION_ID"),"type":os.environ.get("XDG_SESSION_TYPE"),"desktop":os.environ.get("XDG_CURRENT_DESKTOP")},"host":diag.get("host",{}),"planes":diag.get("capabilities",{}),"next":diag.get("next")}
out=pathlib.Path(sys.argv[2]); out.write_text(json.dumps(p,separators=(",",":"))+"\n"); os.chmod(out,0o600)
PY
    mv -f "$tmp_profile" "$PROFILE"; trap - EXIT; rm -f "$tmp_diag"; $QUIET || cat "$PROFILE"; exit 0;;
read)
    if [ ! -s "$PROFILE" ]; then printf '{"schema":"gwcu.profile.v1","ok":false,"code":"profile_missing","retryable":true,"terminal":false,"next":{"action":"refresh_profile"}}\n'; exit 30; fi
    rc=0
    "$PYTHON" - "$PROFILE" <<'PY' || rc=$?
import json,os,pathlib,sys
try: d=json.loads(pathlib.Path(sys.argv[1]).read_text())
except Exception as e:
 print(json.dumps({"schema":"gwcu.profile.v1","ok":False,"code":"profile_corrupt","retryable":True,"terminal":False,"detail":str(e),"next":{"action":"refresh_profile"}},separators=(",",":"))); raise SystemExit(30)
try: boot=pathlib.Path('/proc/sys/kernel/random/boot_id').read_text().strip()
except OSError: boot=None
s=d.get("session",{}); cur=os.environ.get("XDG_SESSION_ID")
if d.get("schema")!="gwcu.profile.v1" or (boot and s.get("boot_id") and boot!=s["boot_id"]) or (cur and s.get("session_id") and cur!=s["session_id"]):
 print(json.dumps({"schema":"gwcu.profile.v1","ok":False,"code":"profile_stale","retryable":True,"terminal":False,"next":{"action":"refresh_profile"}},separators=(",",":"))); raise SystemExit(30)
print(json.dumps(d,separators=(",",":")))
PY
    exit "$rc";;
*) usage; exit 2;;
esac
