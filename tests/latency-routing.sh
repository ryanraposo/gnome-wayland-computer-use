#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

pass() {
    printf 'ok - %s\n' "$1"
}

capture="$ROOT/scripts/capture.sh"
serve="$ROOT/scripts/serve.sh"
hermes_skill="$ROOT/SKILL.md"
portable_skill="$ROOT/runtimes/openai/SKILL.md"

if grep -Eq 'sleep (1\.5|0\.4|0\.2)([[:space:]]|$)' "$capture"; then
    fail "capture helper has no legacy fixed screenshot sleeps"
fi
grep -q '^wait_for_new_screenshot()' "$capture" || \
    fail "capture helper polls for screenshot creation"
grep -q -- '--timing' "$capture" || \
    fail "capture helper exposes timing diagnostics"
pass "capture helper uses polling and timing diagnostics"

grep -q '^## Installed Web App Identity$' "$hermes_skill" || \
    fail "Hermes skill documents standalone web-app identity"
grep -q -- '--app-id=' "$hermes_skill" || \
    fail "Hermes skill recognizes standalone browser launchers"
grep -Fq 'Use `mode="ax"` first' "$hermes_skill" || \
    fail "Hermes skill makes AX the cheap first observation"
grep -q 'do not immediately pay for another capture' "$hermes_skill" || \
    fail "Hermes skill avoids duplicate verification captures"
grep -q '^## Installed Web App Identity$' "$portable_skill" || \
    fail "portable skill documents standalone web-app identity"
pass "runtime routing is AX-first and installed-web-app aware"

grep -q '^## Fast Path$' "$hermes_skill" || \
    fail "Hermes skill documents a fast interaction path"
grep -q 'Call `list_windows` only when app discovery still leaves multiple candidate' "$hermes_skill" || \
    fail "Hermes skill avoids unconditional list_windows"
if grep -q 'computer_use(action="click", element=7, capture_after=true)' "$hermes_skill"; then
    fail "happy-path click example does not force a post-action capture"
fi
grep -q 'Do not add fixed waits between ordinary actions' "$hermes_skill" || \
    fail "Hermes skill forbids routine wait pacing"
grep -q '`focus_app` is an escalation/action tool, not target discovery' "$hermes_skill" || \
    fail "Hermes skill keeps focus changes out of discovery"
pass "interaction loop avoids discovery, wait, focus, and recapture churn"

grep -q 'hermes config set computer_use.no_overlay true' "$serve" || \
    fail "compatibility backend seeds Hermes no-overlay mode"
grep -q 'hermes config set computer_use.max_image_dimension 1152' "$serve" || \
    fail "compatibility backend seeds smaller routine images"
grep -q '^export CUA_DRIVER_RS_TELEMETRY_ENABLED=0$' "$serve" || \
    fail "compatibility backend disables cua-driver telemetry"
pass "Hermes/cua-driver runtime gets low-overhead defaults"

# The ydotool screen fallback should return as soon as the screenshot file
# exists instead of imposing the old 1.5 second sleep.
home="$TEST_TMP/home"
mock_bin="$TEST_TMP/bin"
mkdir -p "$home/Pictures/Screenshots" "$mock_bin"
cat > "$mock_bin/gnome-screenshot" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
exit 1
SH
cat > "$mock_bin/ydotool" <<'SH'
#!/usr/bin/env bash
mkdir -p "$HOME/Pictures/Screenshots"
printf 'png' > "$HOME/Pictures/Screenshots/fast.png"
SH
chmod +x "$mock_bin/"*

start_ms=$(date +%s%3N)
method=$(HOME="$home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" \
    PATH="$mock_bin:/usr/bin:/bin" \
    "$capture" --screen "$TEST_TMP/screen.png")
elapsed_ms=$(( $(date +%s%3N) - start_ms ))
[ "$method" = 'capture_method=ydotool-shift-print' ] || \
    fail "screen capture reaches the mocked ydotool fallback"
[ "$elapsed_ms" -lt 1000 ] || \
    fail "immediate screenshot fallback completes in under one second (got ${elapsed_ms}ms)"
pass "screen fallback returns immediately when capture is ready (${elapsed_ms}ms)"

# Desktop compatibility capture may briefly poll compositor state, but should
# still avoid the former multi-second fixed-delay path.
mock_bin="$TEST_TMP/desktop-bin"
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
case "$*" in
    'key 42:1 99:1 99:0 42:0')
        mkdir -p "$HOME/Pictures/Screenshots"
        printf 'png' > "$HOME/Pictures/Screenshots/desktop-fast.png"
        ;;
esac
SH
chmod +x "$mock_bin/"*

start_ms=$(date +%s%3N)
method=$(HOME="$home" PATH="$mock_bin:/usr/bin:/bin" \
    "$capture" --desktop "$TEST_TMP/desktop.png")
elapsed_ms=$(( $(date +%s%3N) - start_ms ))
[ "$method" = 'capture_method=ydotool-show-desktop' ] || \
    fail "desktop capture reaches the mocked compatibility fallback"
[ "$elapsed_ms" -lt 1000 ] || \
    fail "desktop compatibility fallback completes in under one second (got ${elapsed_ms}ms)"
pass "desktop compatibility path avoids multi-second delay (${elapsed_ms}ms)"

# Timing mode must preserve the normal stdout contract while emitting a
# machine-readable elapsed time on stderr.
mock_bin="$TEST_TMP/timing-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/gnome-screenshot" <<'SH'
#!/usr/bin/env bash
printf 'png' > "$2"
SH
cat > "$mock_bin/gnome-shell" <<'SH'
#!/usr/bin/env bash
printf 'GNOME Shell 48.0\n'
SH
chmod +x "$mock_bin/"*
timing_err="$TEST_TMP/timing.err"
method=$(HOME="$home" PATH="$mock_bin:/usr/bin:/bin" \
    "$capture" --timing --screen "$TEST_TMP/timing.png" 2>"$timing_err")
[ "$method" = 'capture_method=gnome-screenshot' ] || \
    fail "timing mode preserves capture method stdout"
grep -Eq '^capture_elapsed_ms=[0-9]+$' "$timing_err" || \
    fail "timing mode emits machine-readable elapsed milliseconds"
pass "timing mode preserves output and reports elapsed milliseconds"
