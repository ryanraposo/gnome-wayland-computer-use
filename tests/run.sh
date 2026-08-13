#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
passed=0
pass(){ printf 'ok - %s\n' "$1"; ((passed++)) || true; }
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }

[ ! -e "$ROOT/install-core.sh" ] || fail "secondary installer still exists"
[ ! -e "$ROOT/lib/checks.sh" ] || fail "retired shared platform probes still exist"
! grep -Eq 'add_pkg ydotool|modprobe uinput|usermod .*input|CUA_DRIVER_RS_ENABLE_WAYLAND' "$ROOT/install.sh" || fail "installer still provisions raw input or legacy Cua policy"
! grep -Eq 'ExecStart=.*serve\.sh|enable .*gnome-wayland-computer-use\.service' "$ROOT/install.sh" || fail "installer still creates a Cua daemon service"
grep -q 'https://cua.ai/driver/install.sh' "$ROOT/install.sh" || fail "official Cua installer missing"
grep -q 'packages/current/wayland-helper' "$ROOT/install.sh" || fail "Cua packaged helper boundary missing"
grep -q 'health_report' "$ROOT/install.sh" || fail "installer does not require Cua stable health surface"
pass "installer has one Cua-native ownership model"

for pkg in pipewire wireplumber xdg-desktop-portal-gnome gstreamer1.0-pipewire python3-gst-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0 at-spi2-core; do
    grep -q "$pkg" "$ROOT/install.sh" || fail "installer cannot repair $pkg"
done
pass "Ubuntu observation dependencies are explicit"

! grep -Eq 'ydotool|uinput|org\.cua\.WinRects|cua-driver' "$ROOT/scripts/capture.sh" || fail "direct observation fallback owns control machinery"
grep -q 'org.freedesktop.portal.Screenshot' "$ROOT/scripts/capture.sh" || fail "direct observation does not use Screenshot portal"
pass "direct observation fallback is portal-only"

cat >"$TMP/fake-cua" <<'PY'
#!/usr/bin/env python3
import json,sys
if len(sys.argv)<2 or sys.argv[1]!='mcp': raise SystemExit(2)
for line in sys.stdin:
    q=json.loads(line)
    if q.get('method')=='initialize':
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'protocolVersion':'2024-11-05','serverInfo':{'name':'cua-driver','version':'test'}}}),flush=True)
    elif q.get('method')=='tools/call':
        report={'schema_version':'1','platform':'linux','driver_version':'test','overall':'ok','checks':[]}
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'content':[],'isError':False,'structuredContent':report}}),flush=True)
PY
chmod +x "$TMP/fake-cua"
python3 "$ROOT/scripts/cua-health.py" --driver "$TMP/fake-cua" >"$TMP/health.json"
python3 - "$TMP/health.json" <<'PY' || fail "Cua health transport contract failed"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.cua-health.v1' and d['ok'] and d['report']['overall']=='ok'
PY
pass "Cua health is consumed through stable MCP structuredContent"

mkdir -p "$TMP/home"
rc=0
HOME="$TMP/home" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE \
    "$ROOT/scripts/diagnose.sh" --machine >"$TMP/diag.json" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "broken host diagnosis returned success"
python3 - "$TMP/diag.json" <<'PY' || fail "diagnostic envelope is untruthful"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.diagnose.v2'; assert d['ok'] is False; assert d['code']=='wrong_session'; assert 'observation' in d and 'cua' in d
PY
pass "machine diagnosis uses ready-now semantics"

XDG_RUNTIME_DIR="$TMP/runtime" python3 "$ROOT/scripts/observer.py" self-test >"$TMP/observer.json"
python3 - "$TMP/observer.json" <<'PY' || fail "observer self-test invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok'] and d['schema']=='gwcu.observer.selftest.v1'
PY
pass "observer self-test is consent-free"

idh="$TMP/id-home"; data="$idh/data"; mkdir -p "$data/applications" "$idh/runtime" "$TMP/empty"
cat >"$data/app.desktop" <<'D'
[Desktop Entry]
Type=Application
Name=ChatGPT
Exec=/usr/bin/google-chrome-stable --app-id=chatgpt_app
StartupWMClass=crx_chatgpt_app
D
HOME="$idh" XDG_DATA_HOME="$data" XDG_DATA_DIRS="$TMP/empty" XDG_RUNTIME_DIR="$idh/runtime" \
    "$ROOT/scripts/app-identity.sh" --resolve --machine ChatGPT >"$TMP/id.json"
python3 - "$TMP/id.json" <<'PY' || fail "identity resolver failed"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok'] and d['code']=='resolved'
PY
pass "identity resolution stays deterministic"

for f in SKILL.md runtimes/openai/SKILL.md README.md AGENTS.md CAPABILITIES.md DETERMINISM.md; do
    ! grep -Eq 'four-plane|Input recovery' "$ROOT/$f" || fail "$f still documents the retired control plane"
done
pass "published architecture is Cua-native"
printf 'ok - regression suite complete (%d checks)\n' "$passed"
