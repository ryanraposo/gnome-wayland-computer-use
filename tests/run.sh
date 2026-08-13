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

# Repository architecture must contain no project Shell extension.
assert "project capture extension directory is gone" test ! -d "$ROOT/gnome-shell-extension"
assert "capture helper has no WinRects dependency" sh -c '! grep -q "org.cua.WinRects" "$1"' sh "$ROOT/scripts/capture.sh"
assert "capture helper has no project Shell D-Bus dependency" sh -c '! grep -q "GnomeWaylandDesktopCapture" "$1"' sh "$ROOT/scripts/capture.sh"
assert "capture helper never toggles Show Desktop" sh -c '! grep -q "toggle_show_desktop" "$1"' sh "$ROOT/scripts/capture.sh"
assert "capture helper carries a ScreenCast restore token" grep -q 'screencast-restore-token' "$ROOT/scripts/capture.sh"

# Diagnostics: all checks, valid JSON, summary last.
diagnose_home="$TEST_TMP/diagnose-home"
mkdir -p "$diagnose_home"
diagnose_out="$TEST_TMP/diagnose.jsonl"
diagnose_rc=0
HOME="$diagnose_home" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP='KDE"test' \
    "$ROOT/scripts/diagnose.sh" --json > "$diagnose_out" || diagnose_rc=$?
assert "diagnostics return nonzero when core checks fail" test "$diagnose_rc" -ne 0
assert "diagnostics emit all checks plus summary" test "$(wc -l < "$diagnose_out")" -eq 19
assert "diagnostic JSON is valid and names native capture checks" python3 - "$diagnose_out" <<'PY'
import json, pathlib, sys
rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert rows[-1]['check'] == 'summary'
assert rows[-1]['pass'] is False
names = {row['check'] for row in rows}
assert {'screencast_portal','pipewire_capture','screenshot_portal','screencast_restore_token','legacy_capture_extension'} <= names
assert any(row['detail'] == 'KDE"test' for row in rows)
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

# Legacy gnome-screenshot is reachable only after both portal paths fail.
mock_bin="$TEST_TMP/capture-legacy-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat > "$mock_bin/gnome-shell" <<'SH'
#!/usr/bin/env bash
printf 'GNOME Shell 48.0\n'
SH
cat > "$mock_bin/gnome-screenshot" <<'SH'
#!/usr/bin/env bash
printf 'png' > "$2"
SH
chmod +x "$mock_bin/"*
capture_out="$TEST_TMP/legacy.png"
method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out")
assert "legacy GNOME capture remains a recovery rung" test "$method" = 'capture_method=gnome-screenshot'

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
assert "GNOME 50 reaches ydotool only after native portal failures" test "$method" = 'capture_method=ydotool-shift-print'
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
assert "media mode emits attachment marker" sh -c '[[ "$1" == MEDIA:* ]]' sh "$media_out"
assert "media attachment exists" test -s "${media_out#MEDIA:}"
timing_err="$TEST_TMP/timing.err"
method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$TEST_TMP/capture-fast-bin/python3" \
    PATH="$TEST_TMP/capture-fast-bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --timing --screen "$TEST_TMP/timing.png" 2>"$timing_err")
assert "timing preserves method stdout" test "$method" = 'capture_method=portal-screencast'
assert "timing emits elapsed milliseconds" grep -Eq '^capture_elapsed_ms=[0-9]+$' "$timing_err"

# Local installer: migrate old project extension, leave unrelated extension alone.
install_home="$TEST_TMP/install-home"
mock_bin="$TEST_TMP/install-bin"
mkdir -p "$install_home/.hermes/skills/computer-use" "$install_home/.hermes/skills/screenshot" \
    "$install_home/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use" \
    "$install_home/.local/share/gnome-shell/extensions/winrects@example" "$mock_bin"
printf '%s\n' '# My existing Hermes identity' > "$install_home/.hermes/SOUL.md"
printf '%s\n' 'stock Hermes skill' > "$install_home/.hermes/skills/computer-use/SKILL.md"
cat > "$install_home/.hermes/skills/screenshot/SKILL.md" <<'SKILL'
---
name: screenshot
---
Use grim and slurp.
SKILL
for command in gsettings systemctl pkexec sudo hermes cua-driver ydotool ydotoold gnome-screenshot gnome-extensions gst-inspect-1.0; do
    cat > "$mock_bin/$command" <<'SH'
#!/usr/bin/env bash
exit 0
SH
done
cat > "$mock_bin/gdbus" <<'SH'
#!/usr/bin/env bash
printf 'interface org.a11y.Bus\n'
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
assert "installer leaves unrelated WinRects extension alone" test -d "$install_home/.local/share/gnome-shell/extensions/winrects@example"
assert "Hermes override is installed" test -f "$install_home/.hermes/skills/computer-use/SKILL.md"
assert "pre-existing Hermes skill was archived" grep -q 'stock Hermes skill' "$install_home/.hermes/backups/gnome-wayland-computer-use/"*/computer-use/SKILL.md
assert "conflicting screenshot skill was archived" test ! -e "$install_home/.hermes/skills/screenshot"
assert "Hermes routing preserves identity" grep -q 'My existing Hermes identity' "$install_home/.hermes/SOUL.md"
assert "installed version is 2.3.0" grep -qx '2.3.0' "$installed/VERSION"

# Agent-only mode leaves Hermes state alone.
agent_home="$TEST_TMP/agent-home"
agent_bin="$TEST_TMP/agent-bin"
mkdir -p "$agent_home" "$agent_bin"
for command in gsettings systemctl pkexec sudo ydotool ydotoold gnome-screenshot gnome-extensions gst-inspect-1.0 gdbus; do
    cp "$mock_bin/$command" "$agent_bin/$command"
done
HOME="$agent_home" USER=tester XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null PATH="$agent_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended --agent-only >/dev/null
assert "agent-only installs shared stack" test -x "$agent_home/.agents/skills/gnome-wayland-computer-use/scripts/capture.sh"
assert "agent-only creates no Hermes state" test ! -e "$agent_home/.hermes"

# Runtime guidance covers visible-but-inaccessible surfaces.
assert "Hermes skill documents pixel-only surfaces" grep -q '^## Pixel-Only Surfaces$' "$ROOT/SKILL.md"
assert "portable skill documents pixel-only surfaces" grep -q '^## Pixel-Only Surfaces$' "$ROOT/runtimes/openai/SKILL.md"
assert "Hermes skill rejects WinRects dependency" grep -q 'does \*\*not\*\* require WinRects' "$ROOT/SKILL.md"
assert "README states no Shell extension architecture" grep -q 'There is no GNOME Shell extension in the architecture' "$ROOT/README.md"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
