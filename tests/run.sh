#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
passed=0
pass(){ printf 'ok - %s\n' "$1"; ((passed++)) || true; }
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }

installer="$ROOT/install.sh"
uninstaller="$ROOT/uninstall.sh"
teardown="$ROOT/scripts/teardown.sh"

for script in "$installer" "$uninstaller" "$teardown" "$ROOT/scripts/diagnose.sh" "$ROOT/scripts/capture.sh"; do
    bash -n "$script" || fail "shell syntax: ${script#$ROOT/}"
done
pass "shell entrypoints parse"

[ ! -e "$ROOT/install-core.sh" ] || fail "secondary installer still exists"
[ ! -e "$ROOT/lib/checks.sh" ] || fail "retired shared platform probes still exist"
! grep -Eq 'add_pkg ydotool|modprobe uinput|usermod .*input|CUA_DRIVER_RS_ENABLE_WAYLAND' "$installer" || fail "installer still provisions raw input or legacy Cua policy"
! grep -Eq 'ExecStart=.*serve\.sh|enable .*gnome-wayland-computer-use\.service' "$installer" || fail "installer still creates a Cua daemon service"
grep -q 'https://cua.ai/driver/install.sh' "$installer" || fail "official Cua installer missing"
grep -q 'packages/current/wayland-helper' "$installer" || fail "Cua packaged helper boundary missing"
grep -q 'health_report' "$installer" || fail "installer does not require Cua stable health surface"
pass "installer has one Cua-native ownership model"

# Release qualification must be explicit and deterministic.
grep -q 'CUA_DRIVER_RS_VERSION="${GWCU_CUA_DRIVER_RS_VERSION:-0.19.3}"' "$installer" || fail "Cua release pin missing"
grep -q 'CUA_DRIVER_RS_VERSION="$CUA_DRIVER_RS_VERSION"' "$installer" || fail "pin is not forwarded to official Cua installer"
grep -q 'CUA_DRIVER_RS_NO_MODIFY_PATH=1' "$installer" || fail "Cua installer may create unowned PATH edits"
! grep -Eq 'releases/latest|/latest|resolve.*latest|CUA_DRIVER_RS_VERSION=.*latest' "$installer" || fail "installer still depends on latest Cua"
grep -q '/etc/os-release' "$installer" || fail "distro detection missing"
grep -q 'VERSION_ID' "$installer" || fail "Ubuntu version selection missing"
pass "Cua and distro qualification are pinned"

for pkg in pipewire pipewire-bin wireplumber xdg-desktop-portal xdg-desktop-portal-gnome \
    python3-dbus python3-gi python3-gst-1.0 gstreamer1.0-pipewire \
    gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0 at-spi2-core libei1 libxkbcommon0; do
    grep -q "$pkg" "$installer" || fail "installer cannot repair $pkg"
done
grep -q 'dpkg --compare-versions.*0.3.40' "$installer" || fail "PipeWire version floor is not enforced"
for iface in RemoteDesktop ScreenCast Screenshot; do
    grep -q "portal_has $iface" "$installer" || fail "$iface portal check missing"
done
pass "Ubuntu portal/accessibility dependencies are explicit"

# Persistent project service is socket-activated and stale state is reset.
grep -q 'systemctl --user enable --now gnome-wayland-computer-use-observer.socket' "$installer" || fail "observer socket not enabled"
grep -q 'systemctl --user reset-failed' "$installer" || fail "stale user unit failures are not cleared"
! grep -Eq 'KERNEL==.*uinput.*(create|cat|tee)|rules\.d.*>' "$installer" || fail "installer creates a new udev rule"
pass "persistent helper lifecycle is owned"

# Doctor is a hard gate, not decorative output.
grep -q '"$CUA" doctor --json' "$installer" || fail "cua-driver doctor missing"
grep -q 'DOCTOR_RC' "$installer" || fail "doctor exit status is not captured"
grep -q 'doctor_hints' "$installer" || fail "doctor hints are not surfaced"
grep -q 'doctor_mentions_drm' "$installer" || fail "DRM group recovery is not evidence-gated"
grep -q 'adduser "$USER" video' "$installer" || fail "video group recovery missing"
grep -q 'video-group-added' "$teardown" || fail "video group ownership cannot be reversed"
pass "doctor gates readiness and exceptional DRM repair is reversible"

# Root uninstall must exist and reverse owned state, including PATH and units.
[ -f "$uninstaller" ] || fail "root uninstall.sh missing"
grep -q -- '--remove-cua' "$uninstaller" || fail "root uninstaller cannot remove provisioned Cua"
grep -q 'gnome-wayland-computer-use PATH' "$teardown" || fail "managed PATH edits are not reversed"
grep -q 'disable --now "$unit"' "$teardown" || fail "observer units are not disabled"
grep -q 'raw.githubusercontent.com/trycua/cua/cua-driver-rs-v' "$teardown" || fail "pinned Cua uninstaller route missing"
pass "teardown covers project-owned install mutations"

capture="$ROOT/scripts/capture.sh"
! grep -Eq 'ydotool|uinput|org\.cua\.WinRects|cua-driver' "$capture" || fail "direct observation fallback owns control machinery"
grep -q 'org.freedesktop.portal.Screenshot' "$capture" || fail "direct observation does not use Screenshot portal"
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
rc=0
HOME="$idh" XDG_DATA_HOME="$idd" XDG_DATA_DIRS="$TMP/empty-data" XDG_RUNTIME_DIR="$idh/runtime" \
    "$ROOT/scripts/app-identity.sh" --refresh --resolve --machine ChatGPT >"$TMP/id.json" || rc=$?
if [ "$rc" -ne 0 ]; then
    printf 'identity fixture rc=%s output=' "$rc" >&2
    cat "$TMP/id.json" >&2 || true
    printf '\n' >&2
    fail "identity resolver failed"
fi
python3 - "$TMP/id.json" <<'PY' || fail "identity resolver envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok'] and d['code']=='resolved' and d['result']['app_id']=='chatgpt_app'
PY
pass "identity resolution stays deterministic"

for f in SKILL.md runtimes/openai/SKILL.md README.md; do
    grep -qi 'no X11' "$ROOT/$f" || fail "$f does not explicitly preserve GNOME Wayland"
    grep -qi 'Remote Desktop' "$ROOT/$f" || fail "$f does not document remote-control portal consent"
    ! grep -Eqi 'need(s|ed)? (an )?X11|require(s|d)? (an )?X11' "$ROOT/$f" || fail "$f contains outdated X11 requirement"
done
pass "Hermes/agent documentation is portal-native"

for f in SKILL.md runtimes/openai/SKILL.md README.md AGENTS.md CAPABILITIES.md DETERMINISM.md; do
    ! grep -Eq 'four-plane|Input recovery' "$ROOT/$f" || fail "$f still documents the retired control plane"
done
pass "published architecture is Cua-native"
printf 'ok - regression suite complete (%d checks)\n' "$passed"
