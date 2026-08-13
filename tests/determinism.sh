#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }
skill="$ROOT/SKILL.md"; observer="$ROOT/scripts/observer.py"; observe="$ROOT/scripts/observe.sh"; identity="$ROOT/scripts/app-identity.sh"; diagnose="$ROOT/scripts/diagnose.sh"; profile="$ROOT/scripts/profile.sh"; installer="$ROOT/install.sh"; teardown="$ROOT/scripts/teardown.sh"
! grep -q -- '--cached-only' "$skill" || fail "skill still performs first-task cached update"
grep -q 'Do not run update checks, broad diagnostics, or capability inventories before a' "$skill" || fail "skill does not remove housekeeping from success path"
grep -q 'no `list_apps` / `list_windows` ceremony' "$skill" || fail "known targets still invite enumeration"
grep -q 'supplies semantics and pixels together' "$skill" || fail "skill does not reuse one Cua state across AX/PX"
grep -q 'runtime.*effect.*escalation' "$skill" || fail "skill does not consume Cua verdicts"
pass "skill is reflex-oriented instead of housekeeping-oriented"
! grep -q 'org.cua.WinRects' "$observer" || fail "observer imports WinRects protocol"
! grep -q 'org.cua.WinRects' "$observe" || fail "observation facade imports WinRects protocol"
grep -q 'pipewire-serial' "$observer" || fail "broker ignores ScreenCast v6 serial"
grep -q 'target-object' "$observer" || fail "broker cannot prefer PipeWire serial targeting"
grep -q 'set_property("path"' "$observer" || fail "broker lacks older portal compatibility"
grep -q 'DEFAULT_IDLE' "$observer" || fail "broker has no bounded warm lifetime"
grep -q 'op=="status"' "$observer" || fail "broker has no non-capturing status op"
grep -q 'SocketMode=0600' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer socket not private"
grep -q 'DirectoryMode=0700' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer runtime dir not private"
pass "persistent observer is lazy, private, v6-aware, and Cua-independent"
XDG_RUNTIME_DIR="$TMP/runtime" python3 "$observer" self-test >"$TMP/self.json"
python3 - "$TMP/self.json" <<'PY' || fail "observer self-test invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert d['schema']=='gwcu.observer.selftest.v1' and d['ok']
PY
pass "observer self-test requires no portal consent"
idh="$TMP/id-home"; idd="$idh/data"; mkdir -p "$idd/applications" "$idh/runtime" "$TMP/empty-data"
cat >"$idd/applications/chatgpt.desktop" <<'D'
[Desktop Entry]
Type=Application
Name=ChatGPT
Exec=/usr/bin/google-chrome-stable --app-id=chatgpt_app
StartupWMClass=crx_chatgpt_app
D
cat >"$idd/applications/chatgpt-beta.desktop" <<'D'
[Desktop Entry]
Type=Application
Name=ChatGPT Beta
Exec=/usr/bin/google-chrome-stable --app-id=chatgpt_beta
StartupWMClass=crx_chatgpt_beta
D
HOME="$idh" XDG_DATA_HOME="$idd" XDG_DATA_DIRS="$TMP/empty-data" XDG_RUNTIME_DIR="$idh/runtime" "$identity" --resolve --machine ChatGPT >"$TMP/resolved.json"
python3 - "$TMP/resolved.json" <<'PY' || fail "identity exact resolver invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert d['ok'] and d['code']=='resolved' and d['result']['app_id']=='chatgpt_app'
PY
rc=0; HOME="$idh" XDG_DATA_HOME="$idd" XDG_DATA_DIRS="$TMP/empty-data" XDG_RUNTIME_DIR="$idh/runtime" "$identity" --resolve --machine Chat >"$TMP/amb.json" || rc=$?
[ "$rc" -eq 10 ] || fail "ambiguity does not use route-miss exit"
python3 - "$TMP/amb.json" <<'PY' || fail "identity ambiguity invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert not d['ok'] and d['code']=='ambiguous' and len(d['candidates'])==2
PY
pass "identity helper resolves evidence and surfaces ambiguity"
HOME="$TMP/diag-home" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE "$diagnose" --machine >"$TMP/diag.json"
[ "$(wc -l <"$TMP/diag.json")" -eq 1 ] || fail "machine diagnostics emit multiple docs"
python3 - "$TMP/diag.json" <<'PY' || fail "machine diagnostics invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert d['schema']=='gwcu.diagnose.v1' and d['ok'];assert set(d['capabilities'])=={'observation','semantics','gnome_precision','recovery'}
PY
pass "diagnostics compress investigation into one verdict"
HOME="$TMP/profile-home" XDG_STATE_HOME="$TMP/profile-state" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE "$profile" refresh --machine >"$TMP/profile.json"
python3 - "$TMP/profile.json" <<'PY' || fail "profile invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert d['schema']=='gwcu.profile.v1' and d['ok'];assert 'screencast-restore-token' not in json.dumps(d)
PY
[ -s "$TMP/profile-state/gnome-wayland-computer-use/profile.json" ] || fail "profile not persisted"
[ "$(stat -c '%a' "$TMP/profile-state/gnome-wayland-computer-use/profile.json")" = 600 ] || fail "profile not private"
pass "capability profile is passive, atomic, and secret-free"
mkdir -p "$TMP/bin"
cat >"$TMP/fake-observer.py" <<'PY'
import json
print(json.dumps({'schema':'gwcu.observer.v1','ok':False,'code':'broker_unavailable','retryable':True,'terminal':False,'next':{'action':'start_observer_socket'}},separators=(',',':')))
raise SystemExit(30)
PY
cat >"$TMP/direct" <<'SH'
#!/usr/bin/env bash
printf png > "$2"; printf 'capture_method=portal-screencast\n'
SH
cat >"$TMP/bin/systemctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/direct" "$TMP/bin/systemctl"
PATH="$TMP/bin:/usr/bin:/bin" GWCU_OBSERVER_BIN="$TMP/fake-observer.py" GWCU_DIRECT_CAPTURE_BIN="$TMP/direct" GNOME_WAYLAND_SYSTEM_PYTHON=/usr/bin/python3 "$observe" --machine --screen "$TMP/screen.png" >"$TMP/observe.json"
python3 - "$TMP/observe.json" <<'PY' || fail "observe fallback invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert d['ok'] and d['result']['method']=='portal-screencast-direct'
PY
cat >"$TMP/denied.py" <<'PY'
import json
print(json.dumps({'schema':'gwcu.observer.v1','ok':False,'code':'portal_cancelled','retryable':False,'terminal':True,'next':None},separators=(',',':')))
raise SystemExit(20)
PY
cat >"$TMP/must-not" <<'SH'
#!/usr/bin/env bash
touch "$HOME/direct-was-called"; exit 1
SH
chmod +x "$TMP/must-not"; mkdir -p "$TMP/deny-home"; rc=0
HOME="$TMP/deny-home" PATH="$TMP/bin:/usr/bin:/bin" GWCU_OBSERVER_BIN="$TMP/denied.py" GWCU_DIRECT_CAPTURE_BIN="$TMP/must-not" GNOME_WAYLAND_SYSTEM_PYTHON=/usr/bin/python3 "$observe" --machine --screen "$TMP/no.png" >"$TMP/deny.json" || rc=$?
[ "$rc" -eq 20 ] || fail "portal cancellation lost terminal class"; [ ! -e "$TMP/deny-home/direct-was-called" ] || fail "cancellation invoked fallback"
pass "broker failure falls back; consent cancellation terminates"
grep -q 'add_pkg pipewire' "$installer" || fail "installer cannot repair PipeWire"
grep -q 'add_pkg wireplumber' "$installer" || fail "installer cannot repair WirePlumber"
grep -q 'STRIP_FROM_CORE: add_pkg pipewire-pulse' "$installer" || fail "wrapper does not strip audio compatibility from capture repair"
grep -q 'gstreamer1.0-pipewire' "$installer" || fail "installer lost PipeWire bridge boundary"
grep -q 'https://cua.ai/driver/install.sh' "$installer" || fail "installer does not use official Cua installer"
grep -q 'packages/current/wayland-helper' "$installer" || fail "installer lost Cua helper boundary"
grep -q 'ownership.json' "$installer" || fail "installer does not record ownership"
grep -q 'observer.socket' "$installer" || fail "installer does not provision observer"
grep -q 'STRIP_FROM_CORE: Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1' "$installer" || fail "wrapper does not strip obsolete Cua environment override"
grep -q 'PipeWire, WirePlumber, portals, GStreamer' "$teardown" || fail "teardown does not preserve foundation"
pass "Ubuntu/Cua install uses current owners and clean boundaries"
printf 'ok - determinism constitution complete\n'
