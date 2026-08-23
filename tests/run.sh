#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
passed=0
pass(){ printf 'ok - %s\n' "$1"; ((passed++)) || true; }
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }

installer="$ROOT/install.sh"; uninstaller="$ROOT/uninstall.sh"; teardown="$ROOT/scripts/teardown.sh"
profile="$ROOT/scripts/profile.sh"; truths="$ROOT/scripts/truths.py"; portal="$ROOT/scripts/portal-control.py"
worldline="$ROOT/scripts/worldline.py"; capture="$ROOT/scripts/capture.sh"; presenter="$ROOT/scripts/present-window.py"

for s in "$installer" "$uninstaller" "$teardown" "$ROOT/scripts/diagnose.sh" "$capture" "$ROOT/scripts/observe.sh" "$profile" "$ROOT/scripts/computer-use.sh" "$ROOT/scripts/worldline-capture.sh"; do bash -n "$s" || fail "shell syntax: ${s#$ROOT/}"; done
python3 -m py_compile "$ROOT"/scripts/*.py "$ROOT/runtimes/hermes/__init__.py" || fail "Python syntax"
pass "entrypoints parse"

[ ! -e "$ROOT/install-core.sh" ] || fail "secondary installer exists"
! grep -Eq 'add_pkg ydotool|modprobe uinput|usermod .*input|CUA_DRIVER_RS_ENABLE_WAYLAND|ExecStart=.*cua-driver.*serve' "$installer" || fail "installer creates a shadow control plane"
grep -q 'CUA_DRIVER_RS_VERSION="${GWCU_CUA_DRIVER_RS_VERSION:-0.20.0}"' "$installer" || fail "Cua pin missing"
grep -q 'CUA_DRIVER_RS_NO_MODIFY_PATH=1' "$installer" || fail "Cua PATH ownership missing"
grep -q 'https://cua.ai/driver/install.sh' "$installer" || fail "official Cua installer missing"
grep -q 'Qualified Cua Driver.*already installed' "$installer" || fail "qualified Cua is not reused"
grep -q 'packages/current/wayland-helper' "$installer" || fail "Cua helper boundary missing"
pass "Cua remains pinned and sole actuator"

# Physical regression: /etc/os-release contains NAME=Ubuntu and once clobbered
# the installer's own NAME, simultaneously breaking Hermes + WORLDLINE paths.
grep -Fq 'APP_ID="gnome-wayland-computer-use"' "$installer" || fail "installer app identity is not namespaced"
OS_SOURCE_COUNT=$(grep -Ec '^[[:space:]]*\.[[:space:]]+/etc/os-release' "$installer" || true)
[ "$OS_SOURCE_COUNT" -eq 1 ] || fail "os-release must have exactly one controlled source point"
python3 - "$installer" <<'PY' || fail "os-release source is not isolated in a subshell"
import pathlib,sys
lines=pathlib.Path(sys.argv[1]).read_text().splitlines()
start=next(i for i,l in enumerate(lines) if l.strip()=='read_os_release(){')
end=next(i for i,l in enumerate(lines[start+1:],start+1) if l.strip()=='}')
sources=[i for i,l in enumerate(lines) if l.strip()=='. /etc/os-release']
assert len(sources)==1 and start < sources[0] < end
assert any(l.strip()=='(' for l in lines[start+1:sources[0]])
assert any(l.strip()==')' for l in lines[sources[0]+1:end])
PY
grep -Fq 'PLUGIN="$HERMES_HOME/plugins/$APP_ID"' "$installer" || fail "Hermes plugin path can drift from app identity"
pass "Ubuntu metadata cannot clobber GWCU identity"

for pkg in pipewire pipewire-bin wireplumber xdg-desktop-portal xdg-desktop-portal-gnome python3-dbus python3-gi python3-gst-1.0 gstreamer1.0-pipewire gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0 gir1.2-atspi-2.0 at-spi2-core libei1 libxkbcommon0; do grep -q "$pkg" "$installer" || fail "installer cannot repair $pkg"; done
for iface in RemoteDesktop ScreenCast Screenshot; do grep -q "portal_has $iface" "$installer" || fail "$iface portal check missing"; done
pass "Ubuntu portal/accessibility foundation is explicit"

for shipped in scripts/action-span.py scripts/worldline.py scripts/worldline-capture.sh scripts/present-window.py README.md; do grep -q "$shipped" "$installer" || fail "installer omits $shipped"; done
grep -q 'present-window.py" self-test' "$installer" || fail "presentation self-test missing"
grep -q 'present-window.py" status' "$installer" || fail "live presentation qualification missing"
grep -q 'enable --now gnome-wayland-computer-use-worldline.socket' "$installer" || fail "WORLDLINE socket not enabled"
grep -q 'enable --now gnome-wayland-computer-use-observer.socket' "$installer" || fail "observer socket not enabled"
grep -Fq 'ensure_user_daemon worldline "WORLDLINE"' "$installer" || fail "WORLDLINE automatic repair missing"
grep -Fq 'journalctl --user -u "$service_unit"' "$installer" || fail "daemon failure capsule lacks journal evidence"
python3 "$presenter" self-test >/dev/null || fail "presentation primitive self-test"
grep -Fq 'focused' "$presenter" && grep -Fq 'visible' "$presenter" && grep -Fq 'minimized' "$presenter" || fail "presenter does not prove visible focus"
grep -Fq 'pid' "$presenter" && grep -Fq 'window_id' "$presenter" || fail "presenter lacks exact identity"
pass "WORLDLINE, observer and exact presentation are shipped and provable"

# Hermes is a completed integration when detected: no manual enable chore.
grep -Fq 'hermes_exec config set plugins.enabled' "$installer" || fail "Hermes enabled list is not installed"
grep -Fq 'hermes_exec config set plugins.disabled' "$installer" || fail "stale Hermes disable is not repaired"
grep -Fq 'plugins.entries.$APP_ID.granted_capabilities' "$installer" || fail "tools.override grant missing"
grep -Fq 'plugins.entries.$APP_ID.allow_tool_override' "$installer" || fail "legacy override bridge missing"
grep -Fq 'Hermes plugin enabled; computer_use policy is mechanical' "$installer" || fail "plugin enablement is not verified"
! grep -Fqi 'enable it later' "$installer" || fail "installer delegates plugin enablement to user"
grep -q 'plugins disable "$NAME"' "$teardown" || fail "Hermes teardown disable missing"
pass "Hermes policy installation is automatic and reversible"

grep -q 'Enable managed .gwcu local truths?' "$installer" || fail "managed truth prompt missing"
grep -q 'Default visible takeover is faster and deterministic' "$installer" || fail "default control preference not explained"
grep -q 'GWCU_TRUTHS=off' "$installer" || fail "truth override missing"
grep -q 'SCHEMA = "gwcu.truths.v1"' "$truths" || fail "truth schema missing"
grep -q 'nearest_existing' "$truths" || fail "non-Git scope lookup missing"
grep -q 'ensure_gitignore' "$truths" || fail "Git ignore safety missing"
pass ".gwcu remains durable local truth"

grep -q 'portal-control.py.*--authorize' "$installer" || fail "RemoteDesktop bootstrap missing"
grep -q 'for n in 3 2 1' "$installer" || fail "portal countdown missing"
grep -q 'no click or key' "$installer" || fail "minimal handshake explanation missing"
grep -q 'libei-persistent.token' "$portal" || fail "restore-token verification missing"
grep -q '"move_cursor"' "$portal" || fail "pointer-only Cua handshake missing"
! grep -Eq '"name"[[:space:]]*:[[:space:]]*"(click|type_text|key_press)"' "$portal" || fail "portal helper contains invasive actions"
pass "RemoteDesktop consent is explicit and minimally invasive"

grep -Fq 'diagnose.sh" --machine' "$installer" || fail "final installed-state diagnosis missing"
grep -Fq 'gwcu.install-receipt.v1' "$installer" || fail "installer produces no durable proof receipt"
grep -Fq 'install.log' "$installer" || fail "installer has no durable private log"
grep -Fq 'READY // PROVED' "$installer" || fail "success output does not distinguish proved state"
grep -Fq 'INSTALL COMPLETE // ONE GNOME RELOAD REQUIRED' "$installer" || fail "GNOME reload boundary is not honest"
grep -Fq 'presentation_degraded' "$ROOT/scripts/diagnose.sh" || fail "diagnosis can ignore broken exact presentation"
pass "installer ends on unified proof with honest reload boundary"

grep -q 'gnome-wayland-computer-use-worldline.socket' "$teardown" || fail "WORLDLINE unit not removed"
grep -q 'disable --now "$unit"' "$teardown" || fail "user units not disabled"
grep -q 'gnome-wayland-computer-use PATH' "$teardown" || fail "managed PATH block not removed"
grep -q 'Repo/workspace .gwcu files' "$teardown" || fail "workspace truth preservation missing"
grep -q -- '--remove-cua' "$uninstaller" || fail "root uninstall cannot remove provisioned Cua"
pass "teardown removes runtime integration, not workspace truth"

! grep -Eq 'ydotool|uinput|org\.cua\.WinRects|cua-driver' "$capture" || fail "direct observation owns control machinery"
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
d=json.load(open(sys.argv[1]));assert not d['ok'] and d['code']=='wrong_session';assert 'presentation' in d
PY
XDG_RUNTIME_DIR="$TMP/runtime" python3 "$ROOT/scripts/observer.py" self-test >/dev/null || fail "observer self-test"
XDG_RUNTIME_DIR="$TMP/world" python3 "$worldline" self-test >/dev/null || fail "WORLDLINE self-test"
pass "diagnostics and read-only runtimes self-test"

for f in SKILL.md runtimes/openai/SKILL.md README.md; do grep -qi 'Cua' "$ROOT/$f" || fail "$f lost Cua"; grep -qi 'WORLDLINE' "$ROOT/$f" || fail "$f lost WORLDLINE"; grep -qi 'No X11' "$ROOT/$f" || fail "$f lost GNOME Wayland qualification"; grep -qi 'Remote Desktop' "$ROOT/$f" || fail "$f lost consent model"; done
grep -qi 'Observation is an interrupt' "$ROOT/README.md" || fail "README lost core inversion"
grep -qi 'valid until invalidated' "$ROOT/README.md" || fail "README lost invalidation model"
for retired in WORLDLINE.md GWCU.md DETERMINISM.md CAPABILITIES.md PERF_NOTES.md references/skill-ux-contract.md; do [ ! -e "$ROOT/$retired" ] || fail "retired project doc remains: $retired"; done
pass "README is the sole public project documentation surface"

printf 'ok - regression suite complete (%d checks)\n' "$passed"
