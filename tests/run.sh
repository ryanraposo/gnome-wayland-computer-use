#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
passed=0
pass(){ printf 'ok - %s\n' "$1"; ((passed++)) || true; }
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }

installer="$ROOT/install.sh"; uninstaller="$ROOT/uninstall.sh"; teardown="$ROOT/scripts/teardown.sh"
profile="$ROOT/scripts/profile.sh"; truths="$ROOT/scripts/truths.py"; portal="$ROOT/scripts/portal-control.py"
worldline="$ROOT/scripts/worldline.py"; capture="$ROOT/scripts/capture.sh"

for s in "$installer" "$uninstaller" "$teardown" "$ROOT/scripts/diagnose.sh" "$capture" "$ROOT/scripts/observe.sh" "$profile" "$ROOT/scripts/computer-use.sh" "$ROOT/scripts/worldline-capture.sh"; do bash -n "$s" || fail "shell syntax: ${s#$ROOT/}"; done
python3 -m py_compile "$ROOT"/scripts/*.py "$ROOT/runtimes/hermes/__init__.py" || fail "Python syntax"
pass "entrypoints parse"

[ ! -e "$ROOT/install-core.sh" ] || fail "secondary installer exists"
! grep -Eq 'add_pkg ydotool|modprobe uinput|usermod .*input|CUA_DRIVER_RS_ENABLE_WAYLAND|ExecStart=.*cua-driver.*serve' "$installer" || fail "installer creates a shadow control plane"
grep -q 'CUA_DRIVER_RS_VERSION="${GWCU_CUA_DRIVER_RS_VERSION:-0.19.3}"' "$installer" || fail "Cua pin missing"
grep -q 'CUA_DRIVER_RS_NO_MODIFY_PATH=1' "$installer" || fail "Cua PATH ownership missing"
grep -q 'https://cua.ai/driver/install.sh' "$installer" || fail "official Cua installer missing"
grep -q 'Qualified Cua Driver.*already installed' "$installer" || fail "qualified Cua is not reused"
grep -q 'packages/current/wayland-helper' "$installer" || fail "Cua helper boundary missing"
pass "Cua remains pinned and sole actuator"

for pkg in pipewire pipewire-bin wireplumber xdg-desktop-portal xdg-desktop-portal-gnome python3-dbus python3-gi python3-gst-1.0 gstreamer1.0-pipewire gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0 gir1.2-atspi-2.0 at-spi2-core libei1 libxkbcommon0; do grep -q "$pkg" "$installer" || fail "installer cannot repair $pkg"; done
grep -q 'dpkg --compare-versions.*0.3.40' "$installer" || fail "PipeWire floor missing"
for iface in RemoteDesktop ScreenCast Screenshot; do grep -q "portal_has $iface" "$installer" || fail "$iface portal check missing"; done
pass "Ubuntu portal/accessibility foundation is explicit"

grep -q 'scripts/action-span.py' "$installer" || fail "action-span not shipped"
grep -q 'scripts/worldline.py' "$installer" || fail "WORLDLINE daemon not shipped"
grep -q 'scripts/worldline-capture.sh' "$installer" || fail "WORLDLINE capture not shipped"
grep -q 'WORLDLINE.md' "$installer" || fail "WORLDLINE docs not shipped"
grep -q 'enable --now gnome-wayland-computer-use-worldline.socket' "$installer" || fail "WORLDLINE socket not enabled"
grep -q 'enable --now gnome-wayland-computer-use-observer.socket' "$installer" || fail "observer socket not enabled"
grep -q 'worldline.py" self-test' "$installer" || fail "WORLDLINE self-test missing"
grep -q 'observer.py" self-test' "$installer" || fail "observer self-test missing"
pass "WORLDLINE and visual sensor lifecycle ship together"

grep -q 'Enable managed .gwcu local truths?' "$installer" || fail "managed truth prompt missing"
grep -q '/dev/tty' "$installer" || fail "curl-pipe prompt cannot reach terminal"
grep -q 'GWCU_TRUTHS=off' "$installer" || fail "truth override missing"
grep -q 'SCHEMA = "gwcu.truths.v1"' "$truths" || fail "truth schema missing"
grep -q 'nearest_existing' "$truths" || fail "non-Git scope lookup missing"
grep -q 'ensure_gitignore' "$truths" || fail "Git ignore safety missing"
grep -q '"/.gwcu"' "$truths" || fail "root ignore rule missing"
pass ".gwcu remains durable local truth"

grep -q 'portal-control.py.*--authorize' "$installer" || fail "RemoteDesktop bootstrap missing"
grep -q 'for n in 3 2 1' "$installer" || fail "portal countdown missing"
grep -q 'no click or key' "$installer" || fail "minimal handshake explanation missing"
grep -q 'libei-persistent.token' "$portal" || fail "restore-token verification missing"
grep -q '"move_cursor"' "$portal" || fail "pointer-only Cua handshake missing"
! grep -Eq '"name"[[:space:]]*:[[:space:]]*"(click|type_text|key_press)"' "$portal" || fail "portal helper contains invasive actions"
pass "RemoteDesktop consent is explicit and minimally invasive"

grep -q 'hermes plugins enable "$NAME"' "$installer" || fail "Hermes plugin not enabled"
grep -q 'plugins disable "$NAME"' "$teardown" || fail "Hermes plugin not disabled"
grep -q 'doctor_mentions_drm' "$installer" || fail "DRM repair not evidence-gated"
grep -q 'adduser "$LOGIN_USER" video' "$installer" || fail "video-group repair missing"
grep -q 'video-group-added' "$teardown" || fail "video-group ownership not reversible"
pass "integration ownership is reversible"

grep -q 'gnome-wayland-computer-use-worldline.socket' "$teardown" || fail "WORLDLINE unit not removed"
grep -q 'disable --now "$unit"' "$teardown" || fail "user units not disabled"
grep -q 'gnome-wayland-computer-use PATH' "$teardown" || fail "managed PATH block not removed"
grep -q 'Repo/workspace .gwcu files' "$teardown" || fail "workspace truth preservation missing"
grep -q -- '--remove-cua' "$uninstaller" || fail "root uninstall cannot remove provisioned Cua"
pass "teardown removes runtime integration, not workspace truth"

! grep -Eq 'ydotool|uinput|org\.cua\.WinRects|cua-driver' "$capture" || fail "direct observation owns control machinery"
grep -q 'org.freedesktop.portal.Screenshot' "$capture" || fail "direct observation is not portal-only"
! grep -Eq 'ydotool|uinput' "$worldline" || fail "WORLDLINE owns raw input"
grep -q 'Atspi.EventListener' "$worldline" || fail "WORLDLINE AT-SPI adapter missing"
grep -q 'observer_capture' "$worldline" || fail "WORLDLINE visual escalation missing"
pass "read-only sensors stay read-only"

cat >"$TMP/fake-cua" <<'PY'
#!/usr/bin/env python3
import json,sys
if len(sys.argv)<2 or sys.argv[1]!='mcp': raise SystemExit(2)
for line in sys.stdin:
 q=json.loads(line)
 if q.get('method')=='initialize': print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'protocolVersion':'2024-11-05','serverInfo':{'name':'cua-driver','version':'test'}}}),flush=True)
 elif q.get('method')=='tools/call': print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'content':[],'isError':False,'structuredContent':{'schema_version':'1','platform':'linux','driver_version':'test','overall':'ok','checks':[]}}}),flush=True)
PY
chmod +x "$TMP/fake-cua"
python3 "$ROOT/scripts/cua-health.py" --driver "$TMP/fake-cua" >"$TMP/health.json"
python3 - "$TMP/health.json" <<'PY' || fail "health transport contract failed"
import json,sys
d=json.load(open(sys.argv[1]));assert d['schema']=='gwcu.cua-health.v1' and d['ok'] and d['report']['overall']=='ok'
PY
pass "Cua health uses MCP structuredContent"

mkdir -p "$TMP/home"; rc=0
HOME="$TMP/home" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE "$ROOT/scripts/diagnose.sh" --machine >"$TMP/diag.json" 2>/dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "wrong-session diagnosis succeeded"
python3 - "$TMP/diag.json" <<'PY' || fail "diagnostic envelope invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert not d['ok'] and d['code']=='wrong_session'
PY
XDG_RUNTIME_DIR="$TMP/runtime" python3 "$ROOT/scripts/observer.py" self-test >/dev/null || fail "observer self-test"
XDG_RUNTIME_DIR="$TMP/world" python3 "$worldline" self-test >/dev/null || fail "WORLDLINE self-test"
pass "diagnostics and read-only runtimes self-test"

for f in SKILL.md runtimes/openai/SKILL.md README.md DETERMINISM.md CAPABILITIES.md WORLDLINE.md; do grep -qi 'Cua' "$ROOT/$f" || fail "$f lost Cua"; grep -qi 'WORLDLINE' "$ROOT/$f" || fail "$f lost WORLDLINE"; done
for f in SKILL.md runtimes/openai/SKILL.md README.md DETERMINISM.md; do grep -qi 'No X11' "$ROOT/$f" || fail "$f lost GNOME Wayland qualification"; grep -qi 'Remote Desktop' "$ROOT/$f" || fail "$f lost consent model"; done
grep -qi 'Observation is an interrupt' "$ROOT/README.md" || fail "README lost core inversion"
grep -qi 'valid until invalidated' "$ROOT/WORLDLINE.md" || fail "WORLDLINE invalidation model missing"
pass "public project surfaces describe one architecture"

printf 'ok - regression suite complete (%d checks)\n' "$passed"
