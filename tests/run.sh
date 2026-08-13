#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

passed=0
failed=0
pass() { printf 'ok - %s\n' "$1"; ((passed++)) || true; }
fail() { printf 'not ok - %s\n' "$1" >&2; ((failed++)) || true; }
assert() { local name="$1"; shift; if "$@"; then pass "$name"; else fail "$name"; fi; }

# Shared checks.
(
    set -euo pipefail
    # shellcheck disable=SC1091
    . "$ROOT/lib/checks.sh"
    [ "$(XDG_SESSION_TYPE=wayland check_get_session)" = wayland ]
    [ "$(XDG_CURRENT_DESKTOP=GNOME check_get_desktop)" = GNOME ]
    check_version_ge 50.0 49.0
    ! check_version_ge 48.9 49.0
)
assert "shared checks return stable values" test "$?" -eq 0

# Architecture constitution.
assert "project capture extension directory is gone" test ! -d "$ROOT/gnome-shell-extension"
assert "capture helper has no WinRects protocol dependency" sh -c '! grep -q "org.cua.WinRects" "$1"' sh "$ROOT/scripts/capture.sh"
assert "capture helper has no project Shell D-Bus dependency" sh -c '! grep -q "GnomeWaylandDesktopCapture" "$1"' sh "$ROOT/scripts/capture.sh"
assert "capture helper never toggles Show Desktop" sh -c '! grep -q "toggle_show_desktop" "$1"' sh "$ROOT/scripts/capture.sh"
assert "capture helper carries a ScreenCast restore token" grep -q 'screencast-restore-token' "$ROOT/scripts/capture.sh"
assert "installer uses Cua packaged wayland helper" grep -q 'packages/current/wayland-helper' "$ROOT/install.sh"
assert "installer invokes Cua helper installer" grep -q '"$CUA_HELPER_INSTALLER"' "$ROOT/install.sh"
assert "installer never downloads WinRects independently" sh -c '! grep -Eq "curl .*winrects|github.*winrects@cua" "$1"' sh "$ROOT/install.sh"
assert "installer records managed WinRects ownership" grep -q 'cua-winrects-managed' "$ROOT/install.sh"
assert "teardown respects managed WinRects ownership" grep -q 'cua-winrects-managed' "$ROOT/scripts/teardown.sh"
assert "agent-only help promises no Cua acquisition" grep -q 'without Hermes/Cua' "$ROOT/install.sh"
assert "Ubuntu foundation can repair PipeWire" grep -q 'add_pkg pipewire' "$ROOT/install.sh"
assert "Ubuntu foundation can repair WirePlumber" grep -q 'add_pkg wireplumber' "$ROOT/install.sh"
assert "Ubuntu foundation can repair GNOME portal backend" grep -q 'add_pkg xdg-desktop-portal-gnome' "$ROOT/install.sh"
assert "Ubuntu foundation can repair GStreamer PipeWire bridge" grep -q 'add_pkg gstreamer1.0-pipewire' "$ROOT/install.sh"

# Diagnostics: valid JSON, capability rows, meaningful names.
diagnose_home="$TEST_TMP/diagnose-home"
mkdir -p "$diagnose_home"
diagnose_out="$TEST_TMP/diagnose.jsonl"
diagnose_rc=0
HOME="$diagnose_home" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP='KDE"test' \
    "$ROOT/scripts/diagnose.sh" --json > "$diagnose_out" || diagnose_rc=$?
assert "diagnostics return nonzero when core checks fail" test "$diagnose_rc" -ne 0
assert "diagnostic JSON is valid and capability-oriented" python3 - "$diagnose_out" <<'PY'
import json, pathlib, sys
rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
checks = {r.get('check') for r in rows if 'check' in r}
caps = {r.get('capability'): r.get('status') for r in rows if 'capability' in r}
required = {
    'screencast_portal','pipewire_core','wireplumber','pipewire_capture',
    'screenshot_portal','screencast_restore_token','cua_driver',
    'cua_wayland_helper','cua_winrects_installed','cua_winrects_active',
    'cua_winrects_shell_owner','legacy_capture_extension'
}
assert required <= checks
assert {'observation','semantic_control','gnome_precision','input_recovery'} <= caps.keys()
assert any(r.get('detail') == 'KDE"test' for r in rows)
assert rows[-1].get('check') == 'summary'
PY

capture_home="$TEST_TMP/capture-home"
mkdir -p "$capture_home"

# ScreenCast hot path.
mock_bin="$TEST_TMP/capture-fast-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
printf 'png' > "$2"
SH
chmod +x "$mock_bin/python3"
capture_out="$TEST_TMP/screencast.png"
method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out")
assert "capture prefers ScreenCast/PipeWire" test "$method" = 'capture_method=portal-screencast'
assert "ScreenCast path produces output" test -s "$capture_out"

# --desktop is compatibility alias, never a hidden-window surface.
capture_out="$TEST_TMP/desktop-alias.png"
alias_err="$TEST_TMP/desktop-alias.err"
method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --desktop "$capture_out" 2>"$alias_err")
assert "desktop alias uses same ScreenCast path" test "$method" = 'capture_method=portal-screencast'
assert "desktop alias declares visible-screen scope" grep -q 'capture_scope=visible-screen requested=desktop' "$alias_err"

# Technical ScreenCast failure reaches one-shot Screenshot.
mock_bin="$TEST_TMP/capture-fallback-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
count=$(cat "$HOME/portal-count" 2>/dev/null || printf 0)
count=$((count + 1)); printf '%s\n' "$count" > "$HOME/portal-count"
if [ "$count" -eq 1 ]; then exit 1; fi
printf 'png' > "$2"
SH
chmod +x "$mock_bin/python3"
rm -f "$capture_home/portal-count"
capture_out="$TEST_TMP/screenshot-fallback.png"
method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out")
assert "technical ScreenCast failure reaches Screenshot portal" test "$method" = 'capture_method=portal-screenshot'
assert "Screenshot recovery produces output" test -s "$capture_out"
assert "portal recovery uses exactly two attempts" test "$(cat "$capture_home/portal-count")" -eq 2

# User denial stops instead of opening another capture UI.
mock_bin="$TEST_TMP/capture-denied-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
exit 20
SH
cat > "$mock_bin/ydotool" <<'SH'
#!/usr/bin/env bash
touch "$HOME/ydotool-was-called"
exit 0
SH
chmod +x "$mock_bin/"*
rm -f "$capture_home/ydotool-was-called"
rc=0
HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$TEST_TMP/denied.png" >/dev/null 2>&1 || rc=$?
assert "portal denial reports failure" test "$rc" -ne 0
assert "portal denial does not invoke hardware capture" test ! -e "$capture_home/ydotool-was-called"

# GNOME 50 skips gnome-screenshot and can reach ydotool.
mock_bin="$TEST_TMP/capture-ydotool-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat > "$mock_bin/gnome-shell" <<'SH'
#!/usr/bin/env bash
printf 'GNOME Shell 50.1\n'
SH
cat > "$mock_bin/gnome-screenshot" <<'SH'
#!/usr/bin/env bash
touch "$HOME/gnome-screenshot-was-called"
exit 1
SH
cat > "$mock_bin/ydotool" <<'SH'
#!/usr/bin/env bash
mkdir -p "$HOME/Pictures/Screenshots"
printf '%s\n' "$*" > "$HOME/ydotool-args"
printf 'png' > "$HOME/Pictures/Screenshots/Screenshot with spaces.png"
SH
chmod +x "$mock_bin/"*
rm -f "$capture_home/gnome-screenshot-was-called"
capture_out="$TEST_TMP/ydotool.png"
method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out")
assert "GNOME 50 reaches ydotool only after portal failures" test "$method" = 'capture_method=ydotool-shift-print'
assert "GNOME 50 skips broken gnome-screenshot" test ! -e "$capture_home/gnome-screenshot-was-called"
assert "ydotool uses direct full-screen shortcut" grep -qx 'key 42:1 99:1 99:0 42:0' "$capture_home/ydotool-args"

# Total failure preserves an existing output.
mock_bin="$TEST_TMP/capture-fail-bin"
mkdir -p "$mock_bin"
for command in python3 gnome-screenshot ydotool; do
    cat > "$mock_bin/$command" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    chmod +x "$mock_bin/$command"
done
cat > "$mock_bin/gnome-shell" <<'SH'
#!/usr/bin/env bash
printf 'GNOME Shell 50.1\n'
SH
chmod +x "$mock_bin/gnome-shell"
capture_out="$TEST_TMP/preserved.png"
printf original > "$capture_out"
rc=0
HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out" >/dev/null 2>&1 || rc=$?
assert "total capture failure is nonzero" test "$rc" -ne 0
assert "failed capture preserves existing output" test "$(cat "$capture_out")" = original

# Media/timing contracts.
media_out=$(HOME="$capture_home" XDG_RUNTIME_DIR="$TEST_TMP" GNOME_WAYLAND_SYSTEM_PYTHON="$TEST_TMP/capture-fast-bin/python3" \
    PATH="$TEST_TMP/capture-fast-bin:/usr/bin:/bin" "$ROOT/scripts/capture.sh" --media --screen 2>/dev/null)
assert "media mode emits attachment marker" test "${media_out#MEDIA:}" != "$media_out"
assert "media attachment exists" test -s "${media_out#MEDIA:}"
timing_err="$TEST_TMP/timing.err"
method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$TEST_TMP/capture-fast-bin/python3" \
    PATH="$TEST_TMP/capture-fast-bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --timing --screen "$TEST_TMP/timing.png" 2>"$timing_err")
assert "timing preserves method stdout" test "$method" = 'capture_method=portal-screencast'
assert "timing emits elapsed milliseconds" grep -Eq '^capture_elapsed_ms=[0-9]+$' "$timing_err"

# Local Hermes/Cua installer: migrate old project extension, provision only
# Cua's packaged helper, and record ownership.
install_home="$TEST_TMP/install-home"
mock_bin="$TEST_TMP/install-bin"
helper="$install_home/.cua-driver/packages/current/wayland-helper"
mkdir -p "$install_home/.hermes/skills/computer-use" "$install_home/.hermes/skills/screenshot" \
    "$install_home/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use" \
    "$install_home/.local/share/gnome-shell/extensions/unrelated@example" \
    "$helper/winrects@cua" "$mock_bin"
printf '%s\n' '# My existing Hermes identity' > "$install_home/.hermes/SOUL.md"
printf '%s\n' 'stock Hermes skill' > "$install_home/.hermes/skills/computer-use/SKILL.md"
printf '%s\n' 'helper-extension' > "$helper/winrects@cua/extension.js"
printf '%s\n' '{"uuid":"winrects@cua"}' > "$helper/winrects@cua/metadata.json"
cat > "$helper/install.sh" <<'SH'
#!/usr/bin/env bash
set -e
src="$(cd "$(dirname "$0")" && pwd)/winrects@cua"
dst="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/winrects@cua"
mkdir -p "$dst"
cp "$src/extension.js" "$src/metadata.json" "$dst/"
touch "$HOME/cua-helper-invoked"
SH
chmod +x "$helper/install.sh"
cat > "$install_home/.hermes/skills/screenshot/SKILL.md" <<'SKILL'
---
name: screenshot
---
Use grim and slurp.
SKILL

for command in gsettings systemctl pkexec sudo hermes cua-driver ydotool ydotoold gnome-screenshot gst-inspect-1.0 pw-cli; do
    cat > "$mock_bin/$command" <<'SH'
#!/usr/bin/env bash
exit 0
SH
done
cat > "$mock_bin/gnome-extensions" <<'SH'
#!/usr/bin/env bash
# Intentionally not ACTIVE so installer reports a session reload requirement.
if [ "${1:-}" = info ]; then printf 'State: INITIALIZED\n'; fi
exit 0
SH
cat > "$mock_bin/gdbus" <<'SH'
#!/usr/bin/env bash
printf 'interface org.a11y.Bus\n'
printf 'interface org.freedesktop.portal.ScreenCast\n'
printf 'interface org.freedesktop.portal.Screenshot\n'
SH
chmod +x "$mock_bin/"*

wrong_rc=0
HOME="$install_home" USER=tester XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended >/dev/null 2>&1 || wrong_rc=$?
assert "installer rejects non-GNOME-Wayland by default" test "$wrong_rc" -ne 0

HOME="$install_home" USER=tester XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended >/dev/null
installed="$install_home/.agents/skills/gnome-wayland-computer-use"
assert "installer copies portable skill" test -f "$installed/SKILL.md"
assert "installer copies capture helper" test -x "$installed/scripts/capture.sh"
assert "installer ships no project Shell extension" test ! -e "$installed/gnome-shell-extension"
assert "installer retires old project capture extension" test ! -e "$install_home/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use"
assert "installer preserves unrelated extension" test -d "$install_home/.local/share/gnome-shell/extensions/unrelated@example"
assert "installer invoked Cua packaged helper" test -e "$install_home/cua-helper-invoked"
assert "installer installed winrects@cua from Cua package" test -f "$install_home/.local/share/gnome-shell/extensions/winrects@cua/extension.js"
assert "installer records WinRects it caused" test -f "$install_home/.local/state/gnome-wayland-computer-use/cua-winrects-managed"
assert "Hermes override is installed" test -f "$install_home/.hermes/skills/computer-use/SKILL.md"
assert "pre-existing Hermes skill was archived" grep -q 'stock Hermes skill' "$install_home/.hermes/backups/gnome-wayland-computer-use/"*/computer-use/SKILL.md
assert "conflicting screenshot skill was archived" test ! -e "$install_home/.hermes/skills/screenshot"
assert "Hermes routing preserves identity" grep -q 'My existing Hermes identity' "$install_home/.hermes/SOUL.md"
assert "installed version is 2.3.0" grep -qx '2.3.0' "$installed/VERSION"

# Pre-existing Cua WinRects must not become project-owned.
pre_home="$TEST_TMP/pre-home"
pre_bin="$TEST_TMP/pre-bin"
pre_helper="$pre_home/.cua-driver/packages/current/wayland-helper"
mkdir -p "$pre_home/.local/share/gnome-shell/extensions/winrects@cua" "$pre_helper/winrects@cua" "$pre_bin"
printf '%s\n' 'same' > "$pre_home/.local/share/gnome-shell/extensions/winrects@cua/extension.js"
printf '%s\n' '{}' > "$pre_home/.local/share/gnome-shell/extensions/winrects@cua/metadata.json"
printf '%s\n' 'same' > "$pre_helper/winrects@cua/extension.js"
printf '%s\n' '{}' > "$pre_helper/winrects@cua/metadata.json"
cat > "$pre_helper/install.sh" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$pre_helper/install.sh"
for command in gsettings systemctl pkexec sudo hermes cua-driver ydotool ydotoold gnome-screenshot gst-inspect-1.0 pw-cli; do cp "$mock_bin/$command" "$pre_bin/$command"; done
cat > "$pre_bin/gnome-extensions" <<'SH'
#!/usr/bin/env bash
[ "${1:-}" = info ] && printf 'State: ACTIVE\n'
SH
cp "$mock_bin/gdbus" "$pre_bin/gdbus"
chmod +x "$pre_bin/"*
HOME="$pre_home" USER=tester XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null PATH="$pre_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended >/dev/null
assert "pre-existing WinRects remains unowned" test ! -e "$pre_home/.local/state/gnome-wayland-computer-use/cua-winrects-managed"

# Agent-only mode never acquires Cua/WinRects.
agent_home="$TEST_TMP/agent-home"
agent_bin="$TEST_TMP/agent-bin"
mkdir -p "$agent_home" "$agent_bin"
for command in gsettings systemctl pkexec sudo ydotool ydotoold gnome-screenshot gst-inspect-1.0 pw-cli gdbus; do cp "$mock_bin/$command" "$agent_bin/$command"; done
cp "$mock_bin/gnome-extensions" "$agent_bin/gnome-extensions"
HOME="$agent_home" USER=tester XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null PATH="$agent_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended --agent-only >/dev/null
assert "agent-only installs shared stack" test -x "$agent_home/.agents/skills/gnome-wayland-computer-use/scripts/capture.sh"
assert "agent-only creates no Hermes state" test ! -e "$agent_home/.hermes"
assert "agent-only installs no WinRects" test ! -e "$agent_home/.local/share/gnome-shell/extensions/winrects@cua"
assert "agent-only records no WinRects ownership" test ! -e "$agent_home/.local/state/gnome-wayland-computer-use/cua-winrects-managed"

# Runtime/documentation boundaries.
assert "Hermes skill documents pixel-only surfaces" grep -q '^## Pixel-Only Surfaces$' "$ROOT/SKILL.md"
assert "portable skill documents pixel-only surfaces" grep -q '^## Pixel-Only Surfaces$' "$ROOT/runtimes/openai/SKILL.md"
assert "Hermes skill names foreground preservation" grep -q '^## Foreground Preservation Contract$' "$ROOT/SKILL.md"
assert "Hermes skill routes Cua WinRects through runtime" grep -q 'Use the runtime.*Cua capabilities' "$ROOT/SKILL.md"
assert "README names four planes" grep -q 'Version 2.3 has four planes' "$ROOT/README.md"
assert "README keeps ScreenCast independent" grep -q 'Capture order stays independent from Cua' "$ROOT/README.md"
assert "README documents ownership marker" grep -q 'cua-winrects-managed' "$ROOT/README.md"
assert "landing page names Cua precision" grep -q 'Cua + WinRects' "$ROOT/index.html"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
