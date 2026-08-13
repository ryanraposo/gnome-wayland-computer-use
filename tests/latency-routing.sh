#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_TMP=$(mktemp -d)
trap 'rm -rf "$TEST_TMP"' EXIT

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

capture="$ROOT/scripts/capture.sh"
identity="$ROOT/scripts/app-identity.sh"
update_check="$ROOT/scripts/check-update.sh"
hermes_skill="$ROOT/SKILL.md"
portable_skill="$ROOT/runtimes/openai/SKILL.md"
contract="$ROOT/references/skill-ux-contract.md"
installer="$ROOT/install.sh"
landing="$ROOT/index.html"
readme="$ROOT/README.md"

# Capture architecture: persistent ScreenCast is the hot path, not a Shell helper.
grep -q '^capture_portal_screencast()' "$capture" || fail "capture has a ScreenCast hot path"
grep -q "persist_mode.*Variant('u', 2)" "$capture" || fail "ScreenCast requests persistent permission"
grep -q 'screencast-restore-token' "$capture" || fail "ScreenCast persists a restore token"
grep -q 'capture_portal_screencast || portal_rc=' "$capture" || fail "ScreenCast is attempted"
grep -q 'capture_portal_screenshot || portal_rc=' "$capture" || fail "Screenshot recovery is present"
[ "$(grep -n 'capture_portal_screencast || portal_rc=' "$capture" | cut -d: -f1)" -lt \
  "$(grep -n 'capture_portal_screenshot || portal_rc=' "$capture" | cut -d: -f1)" ] || \
    fail "ScreenCast precedes Screenshot"
! grep -q 'org.cua.WinRects' "$capture" || fail "capture is independent of WinRects"
! grep -q 'GnomeWaylandDesktopCapture' "$capture" || fail "capture is independent of project Shell extension"
! grep -q 'toggle_show_desktop' "$capture" || fail "capture never hides windows"
pass "capture hot path is native, persistent, and extension-free"

# First-use update routing must remain network-free.
update_home="$TEST_TMP/update-home"
update_bin="$TEST_TMP/update-bin"
mkdir -p "$update_home" "$update_bin"
cat > "$update_bin/curl" <<'SH'
#!/usr/bin/env bash
touch "$HOME/network-was-called"
sleep 2
printf '9.9.9\n'
SH
chmod +x "$update_bin/curl"
start_ms=$(date +%s%3N)
HOME="$update_home" PATH="$update_bin:/usr/bin:/bin" \
    GNOME_WAYLAND_COMPUTER_USE_UPDATE_STATE_HOME="$update_home/state" \
    "$update_check" --quiet --cached-only >/dev/null
elapsed_ms=$(( $(date +%s%3N) - start_ms ))
[ ! -e "$update_home/network-was-called" ] || fail "cached-only update check invoked the network"
[ "$elapsed_ms" -lt 500 ] || fail "cached-only update check took ${elapsed_ms}ms"
pass "first-use update check is network-free (${elapsed_ms}ms)"

# Installed web apps backed by the same browser retain distinct identity.
identity_home="$TEST_TMP/identity-home"
identity_data="$identity_home/data"
identity_runtime="$identity_home/runtime"
mkdir -p "$identity_data/applications" "$identity_runtime" "$TEST_TMP/empty-data"
cat > "$identity_data/applications/google-chrome.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Google Chrome
Exec=/usr/bin/google-chrome-stable %U
StartupWMClass=google-chrome
DESKTOP
cat > "$identity_data/applications/chatgpt.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=ChatGPT
Exec=/usr/bin/google-chrome-stable --profile-directory=Default --app-id=chatgpt_app
StartupWMClass=crx_chatgpt_app
DESKTOP
cat > "$identity_data/applications/gmail.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Gmail
Exec=/usr/bin/google-chrome-stable --profile-directory=Default --app=https://mail.google.com/
StartupWMClass=crx_gmail_app
DESKTOP
identity_json="$TEST_TMP/identity.json"
HOME="$identity_home" XDG_DATA_HOME="$identity_data" XDG_DATA_DIRS="$TEST_TMP/empty-data" \
    XDG_RUNTIME_DIR="$identity_runtime" bash "$identity" > "$identity_json"
python3 - "$identity_json" <<'PY' || fail "web-app resolver collapsed browser identity"
import json, sys
rows = json.load(open(sys.argv[1], encoding='utf-8'))
by_name = {row['display_name']: row for row in rows}
assert by_name['Google Chrome']['kind'] == 'browser'
assert by_name['ChatGPT']['kind'] == 'installed-web-app'
assert by_name['ChatGPT']['app_id'] == 'chatgpt_app'
assert by_name['Gmail']['kind'] == 'installed-web-app'
assert by_name['ChatGPT']['desktop_id'] != by_name['Gmail']['desktop_id']
PY
pass "installed web apps retain distinct browser-backed identities"

# Mock warm ScreenCast capture: first portal call wins immediately.
home="$TEST_TMP/capture-home"
mock_bin="$TEST_TMP/capture-fast-bin"
mkdir -p "$home" "$mock_bin"
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
printf 'png' > "$2"
SH
chmod +x "$mock_bin/python3"
start_ms=$(date +%s%3N)
method=$(HOME="$home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$capture" --screen "$TEST_TMP/fast.png")
elapsed_ms=$(( $(date +%s%3N) - start_ms ))
[ "$method" = 'capture_method=portal-screencast' ] || fail "ScreenCast mock was not the hot path"
[ -s "$TEST_TMP/fast.png" ] || fail "ScreenCast mock did not write output"
[ "$elapsed_ms" -lt 1000 ] || fail "mock hot path exceeded one second (${elapsed_ms}ms)"
pass "ScreenCast hot path returns immediately when frame is ready (${elapsed_ms}ms)"

# Technical ScreenCast failure falls back to Screenshot; cancellation does not.
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
rm -f "$home/portal-count"
method=$(HOME="$home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$capture" --screen "$TEST_TMP/fallback.png")
[ "$method" = 'capture_method=portal-screenshot' ] || fail "technical ScreenCast failure did not reach Screenshot"
[ "$(cat "$home/portal-count")" -eq 2 ] || fail "portal fallback count was not two"
pass "technical ScreenCast failure reaches one-shot Screenshot recovery"

mock_bin="$TEST_TMP/capture-denied-bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/python3" <<'SH'
#!/usr/bin/env bash
exit 20
SH
cat > "$mock_bin/ydotool" <<'SH'
#!/usr/bin/env bash
touch "$HOME/ydotool-was-called"
SH
chmod +x "$mock_bin/"*
rm -f "$home/ydotool-was-called"
rc=0
HOME="$home" GNOME_WAYLAND_SYSTEM_PYTHON="$mock_bin/python3" PATH="$mock_bin:/usr/bin:/bin" \
    "$capture" --screen "$TEST_TMP/denied.png" >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "denied ScreenCast unexpectedly succeeded"
[ ! -e "$home/ydotool-was-called" ] || fail "denied ScreenCast opened another capture path"
pass "portal denial stops the chain"

# Timing mode preserves stdout while adding machine-readable stderr.
timing_err="$TEST_TMP/timing.err"
method=$(HOME="$home" GNOME_WAYLAND_SYSTEM_PYTHON="$TEST_TMP/capture-fast-bin/python3" \
    PATH="$TEST_TMP/capture-fast-bin:/usr/bin:/bin" \
    "$capture" --timing --screen "$TEST_TMP/timing.png" 2>"$timing_err")
[ "$method" = 'capture_method=portal-screencast' ] || fail "timing changed capture stdout"
grep -Eq '^capture_elapsed_ms=[0-9]+$' "$timing_err" || fail "timing did not emit elapsed milliseconds"
pass "timing mode preserves method output"

# Runtime/published surfaces share the same architecture.
grep -q '^## Pixel-Only Surfaces$' "$hermes_skill" || fail "Hermes skill lacks pixel-only recovery"
grep -q '^## Pixel-Only Surfaces$' "$portable_skill" || fail "portable skill lacks pixel-only recovery"
grep -q 'does not require WinRects' "$hermes_skill" || fail "Hermes skill still depends on WinRects"
grep -q 'Route once → cheapest truthful evidence' "$readme" || fail "README lost latency contract"
grep -q 'Installed web apps stay apps' "$landing" || fail "landing page lost PWA identity"
grep -q 'ScreenCast + PipeWire' "$landing" || fail "landing page lost native capture hot path"
grep -q 'A fresh screenshot is not a phase-transition requirement' "$contract" || fail "skill UX contract lost decision-boundary rule"
pass "runtime and published surfaces share the extension-free contract"
