#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

passed=0
failed=0

pass() {
    printf 'ok - %s\n' "$1"
    ((passed++)) || true
}

fail() {
    printf 'not ok - %s\n' "$1" >&2
    ((failed++)) || true
}

assert() {
    local name="$1"
    shift
    if "$@"; then pass "$name"; else fail "$name"; fi
}

# Shared library: environment values are returned without executing stray commands.
(
    set -euo pipefail
    # shellcheck disable=SC1091  # ROOT is computed at runtime.
    . "$ROOT/lib/checks.sh"
    [ "$(XDG_SESSION_TYPE=wayland check_get_session)" = wayland ]
    [ "$(XDG_CURRENT_DESKTOP=GNOME check_get_desktop)" = GNOME ]
    check_version_ge 49.1 49.0
    ! check_version_ge 48.9 49.0
)
assert "shared checks return stable values" test "$?" -eq 0

# Diagnostics must report every check, escape JSON, and fail only after the summary.
diagnose_out="$TEST_TMP/diagnose.jsonl"
diagnose_rc=0
XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP='KDE"test' \
    "$ROOT/scripts/diagnose.sh" --json > "$diagnose_out" || diagnose_rc=$?
assert "diagnostics return nonzero when checks fail" test "$diagnose_rc" -ne 0
assert "diagnostics report all checks plus summary" test "$(wc -l < "$diagnose_out")" -eq 15
assert "diagnostic JSON is valid" python3 - "$diagnose_out" <<'PY'
import json
import pathlib
import sys

rows = [json.loads(line) for line in pathlib.Path(sys.argv[1]).read_text().splitlines()]
assert rows[-1]["check"] == "summary"
assert rows[-1]["pass"] is False
assert any(row["detail"] == 'KDE"test' for row in rows)
assert {
    row["check"]: row["detail"]
    for row in rows
}.get("hermes_skill") == "not_selected"
PY

# Desktop capture: the first-class compositor rung writes the desktop layer.
capture_home="$TEST_TMP/capture-home"
mkdir -p "$capture_home"
mock_bin="$TEST_TMP/capture-desktop-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gdbus" <<'SH'
#!/usr/bin/env bash
for last; do :; done
[ "$(dirname "$last")" = "$XDG_RUNTIME_DIR" ] || exit 1
printf 'png' > "$last"
printf "(true, '%s', '{\"focus_unchanged\":true,\"window_state_unchanged\":true}')\n" "$last"
SH
chmod +x "$mock_bin/gdbus"
mkdir -p "$capture_home/output"
capture_out="$capture_home/output/desktop.png"
capture_method=$(HOME="$capture_home" XDG_RUNTIME_DIR="$TEST_TMP" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --desktop "$capture_out")
assert "desktop capture prefers the focus-free compositor rung" \
    test "$capture_method" = "capture_method=gnome-shell-desktop"
assert "compositor desktop capture produces a nonempty output" test -s "$capture_out"
assert "compositor capture supports output outside its restricted staging directory" \
    test "$(dirname "$capture_out")" != "$TEST_TMP"

# Desktop capture: compatibility mode reveals, captures, then restores desktop.
mock_bin="$TEST_TMP/capture-desktop-compat-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gdbus" <<'SH'
#!/usr/bin/env bash
case "$*" in
    *CaptureDesktop*) exit 1 ;;
    *GetRects*) printf '%s\n' '([{"visible":true}])' ;;
    *) exit 1 ;;
esac
SH
cat > "$mock_bin/ydotool" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$HOME/desktop-ydotool-args"
case "$*" in
    'key 42:1 99:1 99:0 42:0')
        mkdir -p "$HOME/Pictures/Screenshots"
        printf 'png' > "$HOME/Pictures/Screenshots/Desktop capture.png"
        ;;
esac
SH
chmod +x "$mock_bin/"*
capture_out="$TEST_TMP/desktop-compat.png"
capture_method=$(HOME="$capture_home" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --desktop "$capture_out")
assert "desktop capture reaches reversible compatibility rung" \
    test "$capture_method" = "capture_method=ydotool-show-desktop"
assert "compatibility rung produces a nonempty desktop" test -s "$capture_out"
assert "compatibility rung restores show-desktop state" \
    test "$(grep -cx 'key 125:1 32:1 32:0 125:0' "$capture_home/desktop-ydotool-args")" -eq 2
assert "compatibility rung takes one full-screen image" \
    test "$(grep -cx 'key 42:1 99:1 99:0 42:0' "$capture_home/desktop-ydotool-args")" -eq 1

# Desktop capture must not claim recovery when compositor state is unavailable.
mock_bin="$TEST_TMP/capture-desktop-unverified-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gdbus" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat > "$mock_bin/ydotool" <<'SH'
#!/usr/bin/env bash
touch "$HOME/unverified-ydotool-was-called"
exit 0
SH
chmod +x "$mock_bin/"*
capture_out="$TEST_TMP/desktop-unverified.png"
printf 'original' > "$capture_out"
capture_rc=0
HOME="$capture_home" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --desktop "$capture_out" >/dev/null 2>&1 || capture_rc=$?
assert "desktop fallback fails closed without compositor state proof" \
    test "$capture_rc" -ne 0
assert "unverified desktop fallback does not synthesize input" \
    test ! -e "$capture_home/unverified-ydotool-was-called"
assert "unverified desktop fallback preserves existing output" \
    test "$(cat "$capture_out")" = original

# Capture: successful first rung writes the requested output.
mock_bin="$TEST_TMP/capture-success-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gnome-screenshot" <<'SH'
#!/usr/bin/env bash
printf 'png' > "$2"
SH
cat > "$mock_bin/gnome-shell" <<'SH'
#!/usr/bin/env bash
printf 'GNOME Shell 48.0\n'
SH
chmod +x "$mock_bin/gnome-screenshot" "$mock_bin/gnome-shell"
capture_out="$TEST_TMP/success.png"
capture_method=$(HOME="$capture_home" PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out")
assert "capture uses gnome-screenshot when available" test "$capture_method" = "capture_method=gnome-screenshot"
assert "capture produces a nonempty output" test -s "$capture_out"

# Capture: the non-interactive Screenshot portal is preferred over ScreenCast.
mock_bin="$TEST_TMP/capture-portal-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gnome-screenshot" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
printf 'png' > "$2"
SH
chmod +x "$mock_bin/"*
capture_out="$TEST_TMP/portal.png"
capture_method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out")
assert "capture prefers the Screenshot portal" \
    test "$capture_method" = "capture_method=portal-screenshot"
assert "Screenshot portal capture produces a nonempty output" test -s "$capture_out"

# Capture: total failure preserves a pre-existing output.
mock_bin="$TEST_TMP/capture-fail-bin"
mkdir -p "$mock_bin"
for command in gnome-screenshot python3 ydotool; do
    cat > "$mock_bin/$command" <<'SH'
#!/usr/bin/env bash
exit 1
SH
    chmod +x "$mock_bin/$command"
done
capture_out="$TEST_TMP/preserved.png"
printf 'original' > "$capture_out"
capture_rc=0
HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out" >/dev/null 2>&1 || capture_rc=$?
assert "capture reports total failure" test "$capture_rc" -ne 0
assert "failed capture preserves existing output" test "$(cat "$capture_out")" = original

# Capture: ydotool fallback requests a full screen and handles spaces in names.
mock_bin="$TEST_TMP/capture-ydotool-bin"
mkdir -p "$mock_bin"
for command in gnome-screenshot python3; do
    cat > "$mock_bin/$command" <<'SH'
#!/usr/bin/env bash
if [ "$(basename "$0")" = python3 ]; then
    count=$(cat "$HOME/portal-call-count" 2>/dev/null || printf '0')
    printf '%s\n' "$((count + 1))" > "$HOME/portal-call-count"
fi
exit 1
SH
    chmod +x "$mock_bin/$command"
done
cat > "$mock_bin/ydotool" <<'SH'
#!/usr/bin/env bash
mkdir -p "$HOME/Pictures/Screenshots"
printf '%s\n' "$*" > "$HOME/ydotool-args"
printf 'png' > "$HOME/Pictures/Screenshots/Screenshot with spaces.png"
SH
chmod +x "$mock_bin/"*
capture_out="$TEST_TMP/ydotool.png"
capture_method=$(HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$capture_out")
assert "capture reaches the ydotool fallback" test "$capture_method" = "capture_method=ydotool-shift-print"
assert "ydotool capture produces a nonempty output" test -s "$capture_out"
assert "ydotool fallback invokes GNOME full-screen shortcut" \
    grep -qx 'key 42:1 99:1 99:0 42:0' "$capture_home/ydotool-args"
assert "default fallback does not open a ScreenCast chooser" \
    test "$(cat "$capture_home/portal-call-count")" -eq 1

# Capture: media mode owns the timestamp and emits the Hermes attachment line.
media_out=$(HOME="$capture_home" XDG_RUNTIME_DIR="$TEST_TMP" \
    PATH="$TEST_TMP/capture-success-bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --media --screen 2>/dev/null)
assert "media mode emits an attachment line" \
    test "${media_out#MEDIA:}" != "$media_out"
assert "media mode attachment exists" test -s "${media_out#MEDIA:}"

# Capture: cancelling portal consent must not unexpectedly open another UI.
mock_bin="$TEST_TMP/capture-denied-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gnome-screenshot" <<'SH'
#!/usr/bin/env bash
exit 1
SH
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
capture_rc=0
HOME="$capture_home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/scripts/capture.sh" --screen "$TEST_TMP/denied.png" >/dev/null 2>&1 || capture_rc=$?
assert "portal cancellation reports failure" test "$capture_rc" -ne 0
assert "portal cancellation does not open screenshot fallback UI" \
    test ! -e "$capture_home/ydotool-was-called"

# Local installation must install a complete, runnable skill bundle.
install_home="$TEST_TMP/install-home"
mock_bin="$TEST_TMP/install-bin"
mkdir -p "$install_home" "$mock_bin"
install_help=$("$ROOT/install.sh" --help)
assert "installer advertises both runtime modes" \
    test "$(grep -Ec -- '--hermes|--agent-only' <<< "$install_help")" -ge 2
conflict_rc=0
"$ROOT/install.sh" --hermes --agent-only >/dev/null 2>&1 || conflict_rc=$?
assert "installer rejects conflicting runtime modes" test "$conflict_rc" -ne 0
printf '%s\n' '# My existing Hermes identity' > "$install_home/.hermes-soul-original"
mkdir -p "$install_home/.hermes"
cp "$install_home/.hermes-soul-original" "$install_home/.hermes/SOUL.md"
mkdir -p "$install_home/.hermes/skills/computer-use" \
    "$install_home/.hermes/skills/screenshot" \
    "$install_home/.hermes/skills/gnome-wayland-computer-use"
printf '%s\n' 'stock Hermes skill' > "$install_home/.hermes/skills/computer-use/SKILL.md"
cat > "$install_home/.hermes/skills/screenshot/SKILL.md" <<'SKILL'
---
name: Screenshot
slug: screenshot
---
On Linux Wayland, use grim and slurp.
SKILL
cat > "$install_home/.hermes/skills/gnome-wayland-computer-use/SKILL.md" <<'SKILL'
---
name: gnome-wayland-computer-use
---
Legacy managed location.
SKILL
for command in gsettings systemctl sudo hermes cua-driver ydotool ydotoold gnome-screenshot gnome-extensions; do
    cat > "$mock_bin/$command" <<'SH'
#!/usr/bin/env bash
exit 0
SH
done
cat > "$mock_bin/gdbus" <<'SH'
#!/usr/bin/env bash
printf 'interface org.a11y.Bus\n'
SH
cat > "$mock_bin/gst-inspect-1.0" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$mock_bin/"*
wrong_env_rc=0
HOME="$install_home" USER=tester XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended >/dev/null 2>&1 || wrong_env_rc=$?
assert "installer rejects a non-GNOME-Wayland session by default" \
    test "$wrong_env_rc" -ne 0
assert "failed environment preflight does not install files" \
    test ! -e "$install_home/.agents/skills/gnome-wayland-computer-use"

HOME="$install_home" USER=tester XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended >/dev/null
installed="$install_home/.agents/skills/gnome-wayland-computer-use"
assert "installer copies the skill" test -f "$installed/SKILL.md"
assert "shared skill name matches its Agent Skills directory" \
    grep -qx 'name: gnome-wayland-computer-use' "$installed/SKILL.md"
shared_description=$(sed -n 's/^description: //p' "$installed/SKILL.md")
canonical_description=$(sed -n 's/^description: //p' "$ROOT/SKILL.md")
assert "shared skill description stays within the 64-character common limit" \
    test "${#shared_description}" -le 64
assert "shared skill description includes platform and activation intents" \
    test "$shared_description" = \
        "Use for Ubuntu GNOME Wayland control, capture, or diagnostics."
assert "canonical and shared skill descriptions stay aligned" \
    test "$canonical_description" = "$shared_description"
assert "shared skill uses only universally required frontmatter" \
    awk '
        /^---$/ { delimiters++; next }
        delimiters == 1 && /^[^[:space:]]/ {
            key = $0
            sub(/:.*/, "", key)
            if (key != "name" && key != "description") bad = 1
        }
        END { exit bad || delimiters < 2 }
    ' "$installed/SKILL.md"
assert "shared skill teaches native agent dispatch" \
    grep -q "native computer-use" "$installed/SKILL.md"
assert "shared skill routes capture through its own installed bundle" \
    grep -q '\.agents/skills/gnome-wayland-computer-use' "$installed/SKILL.md"
assert "shared skill does not depend on the Hermes skill path" \
    test "$(grep -c '\.hermes/skills/computer-use' "$installed/SKILL.md")" -eq 0
assert "installer copies shared checks" test -f "$installed/lib/checks.sh"
assert "installer copies capture helper" test -x "$installed/scripts/capture.sh"
assert "installer copies diagnostic helper" test -x "$installed/scripts/diagnose.sh"
assert "installer copies backend helper" test -x "$installed/scripts/serve.sh"
assert "installer copies teardown helper" test -x "$installed/scripts/teardown.sh"
assert "installer bundles the desktop capture extension" \
    test -f "$installed/gnome-shell-extension/extension.js"
assert "installer activates the desktop capture extension" \
    test -f "$install_home/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use/extension.js"
assert "installer always copies the Hermes skill" \
    test -f "$install_home/.hermes/skills/computer-use/SKILL.md"
assert "Hermes override shadows the built-in computer-use skill" \
    cmp -s "$ROOT/SKILL.md" "$install_home/.hermes/skills/computer-use/SKILL.md"
assert "Hermes install records mode for diagnostics" \
    test -f "$installed/.hermes-integration"
assert "installer archives a pre-existing computer-use skill" \
    grep -q 'stock Hermes skill' "$install_home/.hermes/backups/gnome-wayland-computer-use/"*/computer-use/SKILL.md
assert "installer quarantines conflicting learned screenshot skills" \
    test ! -e "$install_home/.hermes/skills/screenshot"
assert "quarantined screenshot skill remains recoverable" \
    test -f "$install_home/.hermes/backups/gnome-wayland-computer-use/"*/screenshot/SKILL.md
assert "legacy Hermes skill is archived instead of deleted" \
    grep -q 'Legacy managed location' \
        "$install_home/.hermes/backups/gnome-wayland-computer-use/"*/gnome-wayland-computer-use/SKILL.md
assert "Hermes skill routes whole-desktop capture through the helper" \
    grep -q '\.hermes/skills/computer-use/scripts/capture\.sh' "$ROOT/SKILL.md"
assert "installer activates always-loaded desktop routing" \
    grep -q 'gnome-wayland-computer-use:start' "$install_home/.hermes/SOUL.md"
assert "installer preserves the existing Hermes identity" \
    grep -q 'My existing Hermes identity' "$install_home/.hermes/SOUL.md"

# Teardown removes only the managed override and restores archived user skills.
HOME="$install_home" USER=tester HERMES_HOME="$install_home/.hermes" \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$installed/scripts/teardown.sh" --force >/dev/null
assert "teardown restores the pre-existing computer-use skill" \
    grep -q 'stock Hermes skill' "$install_home/.hermes/skills/computer-use/SKILL.md"
assert "teardown restores the learned screenshot skill" \
    test -f "$install_home/.hermes/skills/screenshot/SKILL.md"
assert "teardown restores the legacy Hermes skill" \
    grep -q 'Legacy managed location' \
        "$install_home/.hermes/skills/gnome-wayland-computer-use/SKILL.md"
assert "teardown removes the desktop capture extension" \
    test ! -e "$install_home/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use"
assert "teardown removes only the managed SOUL block" \
    test "$(grep -c 'gnome-wayland-computer-use:start' "$install_home/.hermes/SOUL.md")" -eq 0
assert "teardown preserves the original Hermes identity" \
    grep -q 'My existing Hermes identity' "$install_home/.hermes/SOUL.md"

# Without Hermes, auto mode installs the complete shared stack and leaves
# Hermes-owned state alone.
agent_bin="$TEST_TMP/install-agent-bin"
agent_home="$TEST_TMP/install-agent-home"
mkdir -p "$agent_bin" "$agent_home"
for command in gsettings systemctl sudo ydotool ydotoold gnome-screenshot gnome-extensions gdbus gst-inspect-1.0; do
    cp "$mock_bin/$command" "$agent_bin/$command"
done
agent_install_out="$TEST_TMP/agent-install.out"
HOME="$agent_home" USER=tester XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null \
    PATH="$agent_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended > "$agent_install_out"
agent_skill="$agent_home/.agents/skills/gnome-wayland-computer-use"
assert "auto mode succeeds without Hermes" \
    grep -q 'Shared GNOME host stack ready' "$agent_install_out"
assert "non-Hermes install includes the portable skill and helpers" \
    test -x "$agent_skill/scripts/capture.sh"
assert "non-Hermes install does not create Hermes state" \
    test ! -e "$agent_home/.hermes"
assert "non-Hermes install does not create the Hermes backend service" \
    test ! -e "$agent_home/.config/systemd/user/gnome-wayland-computer-use.service"
assert "non-Hermes install is marked as shared-only" \
    test ! -e "$agent_skill/.hermes-integration"

# Explicit agent-only mode wins even when Hermes is available.
agent_only_home="$TEST_TMP/install-agent-only-home"
mkdir -p "$agent_only_home"
HOME="$agent_only_home" USER=tester XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended --agent-only >/dev/null
assert "agent-only mode skips an available Hermes runtime" \
    test ! -e "$agent_only_home/.hermes"
assert "agent-only mode still installs the portable stack" \
    test -x "$agent_only_home/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh"

# Explicit Hermes mode fails before changing the host when Hermes is absent.
required_home="$TEST_TMP/install-hermes-required-home"
mkdir -p "$required_home"
required_rc=0
HOME="$required_home" USER=tester XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
    GNOME_WAYLAND_UINPUT_DEVICE=/dev/null \
    PATH="$agent_bin:/usr/bin:/bin" \
    "$ROOT/install.sh" --unattended --hermes >/dev/null 2>&1 || required_rc=$?
assert "explicit Hermes mode rejects a missing Hermes runtime" \
    test "$required_rc" -ne 0
assert "failed explicit Hermes preflight makes no host changes" \
    test ! -e "$required_home/.agents"

# The actual curl-pipe execution has no BASH_SOURCE path; all bundle files
# must therefore come from the published asset URLs, never the caller's cwd.
cat > "$mock_bin/curl" <<'SH'
#!/usr/bin/env bash
out=
url=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        --retry) shift 2 ;;
        -*) shift ;;
        *) url="$1"; shift ;;
    esac
done
rel=${url#*gnome-wayland-computer-use/}
mkdir -p "$(dirname "$out")"
cp "$MOCK_SOURCE_ROOT/$rel" "$out"
SH
chmod +x "$mock_bin/curl"
remote_home="$TEST_TMP/remote-home"
remote_cwd="$TEST_TMP/empty-cwd"
mkdir -p "$remote_home" "$remote_cwd"
(
    cd "$remote_cwd"
    HOME="$remote_home" USER=tester MOCK_SOURCE_ROOT="$ROOT" \
        GNOME_WAYLAND_UINPUT_DEVICE=/dev/null \
        XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=GNOME \
        PATH="$mock_bin:/usr/bin:/bin" \
        bash < "$ROOT/install.sh" >/dev/null
)
remote_skill="$remote_home/.hermes/skills/computer-use"
assert "curl-pipe mode downloads the complete Hermes bundle" \
    test -x "$remote_skill/scripts/serve.sh"
assert "curl-pipe mode installs the published skill content" \
    cmp -s "$ROOT/SKILL.md" "$remote_skill/SKILL.md"

printf '\n%d passed, %d failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]
