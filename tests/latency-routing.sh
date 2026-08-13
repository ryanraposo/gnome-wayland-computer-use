#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }
observer="$ROOT/scripts/observer.py"; observe="$ROOT/scripts/observe.sh"; capture="$ROOT/scripts/capture.sh"; skill="$ROOT/SKILL.md"

grep -q 'DEFAULT_IDLE' "$observer" || fail "observer lost bounded warm lifetime"
grep -q 'pipewire-serial' "$observer" || fail "observer lost ScreenCast v6 targeting"
grep -q 'target-object' "$observer" || fail "observer lost PipeWire serial preference"
grep -q 'SocketMode=0600' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer socket is not private"
grep -q 'DirectoryMode=0700' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer directory is not private"
pass "warm observer remains lazy, private and v6-aware"

grep -q 'broker_capture' "$observe" || fail "observe facade lost broker hot path"
grep -q 'DIRECT_CAPTURE' "$observe" || fail "observe facade lost process fallback"
! grep -Eq 'ydotool|uinput' "$capture" || fail "direct observation fallback injects input"
pass "observation fallback cannot mutate foreground through raw input"

mkdir -p "$TMP/bin"
cat >"$TMP/fake-observer.py" <<'PY'
import json
print(json.dumps({'schema':'gwcu.observer.v1','ok':False,'code':'broker_unavailable','retryable':True,'terminal':False,'next':{'action':'start_observer_socket'}},separators=(',',':')))
raise SystemExit(30)
PY
cat >"$TMP/direct" <<'SH'
#!/usr/bin/env bash
printf png > "$2"; printf 'capture_method=portal-screenshot\n'
SH
cat >"$TMP/bin/systemctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/direct" "$TMP/bin/systemctl"
PATH="$TMP/bin:/usr/bin:/bin" GWCU_OBSERVER_BIN="$TMP/fake-observer.py" GWCU_DIRECT_CAPTURE_BIN="$TMP/direct" GNOME_WAYLAND_SYSTEM_PYTHON=/usr/bin/python3 \
    "$observe" --machine --screen "$TMP/screen.png" >"$TMP/observe.json"
python3 - "$TMP/observe.json" <<'PY' || fail "direct fallback envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok']; assert d['result']['method']=='portal-screenshot-direct'
PY
pass "broker transport failure falls through once"

cat >"$TMP/denied.py" <<'PY'
import json
print(json.dumps({'schema':'gwcu.observer.v1','ok':False,'code':'portal_cancelled','retryable':False,'terminal':True,'next':None},separators=(',',':')))
raise SystemExit(20)
PY
cat >"$TMP/must-not" <<'SH'
#!/usr/bin/env bash
touch "$HOME/direct-called"; exit 1
SH
chmod +x "$TMP/must-not"; mkdir -p "$TMP/home"
rc=0
HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" GWCU_OBSERVER_BIN="$TMP/denied.py" GWCU_DIRECT_CAPTURE_BIN="$TMP/must-not" GNOME_WAYLAND_SYSTEM_PYTHON=/usr/bin/python3 \
    "$observe" --machine --screen "$TMP/no.png" >"$TMP/deny.json" || rc=$?
[ "$rc" -eq 20 ] || fail "portal cancellation lost terminal exit class"
[ ! -e "$TMP/home/direct-called" ] || fail "portal cancellation opened another capture path"
pass "consent cancellation is terminal"

grep -q 'Known app means no `list_apps` / `list_windows` ceremony' "$skill" || fail "skill lost known-target latency rule"
grep -q 'Cua state once' "$skill" || fail "skill lost one-state action span"
pass "agent latency contract stays target-scoped"
