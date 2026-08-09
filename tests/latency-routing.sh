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
identity="$ROOT/scripts/app-identity.sh"
update_check="$ROOT/scripts/check-update.sh"
hermes_skill="$ROOT/SKILL.md"
portable_skill="$ROOT/runtimes/openai/SKILL.md"
contract="$ROOT/references/skill-ux-contract.md"
installer="$ROOT/install.sh"

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
grep -q -- 'app-identity.sh' "$hermes_skill" || \
    fail "Hermes skill uses the installed app identity resolver"
grep -q -- '--app-id=' "$hermes_skill" || \
    fail "Hermes skill recognizes standalone browser launchers"
grep -Fq 'Use `mode="ax"` first' "$hermes_skill" || \
    fail "Hermes skill makes AX the cheap first observation"
grep -q '^## Latency-First Interaction$' "$hermes_skill" || \
    fail "Hermes skill defines end-to-end latency policy"
grep -q 'largest deterministic semantic action span' "$hermes_skill" || \
    fail "Hermes skill batches deterministic interaction spans"
grep -q 'do not immediately pay for another observation' "$hermes_skill" || \
    fail "Hermes skill avoids duplicate verification observations"
grep -q -- '--cached-only' "$hermes_skill" || \
    fail "Hermes first-use update check stays off the network"
grep -q '^## Installed Web App Identity$' "$portable_skill" || \
    fail "portable skill documents standalone web-app identity"
grep -q '^## Latency-First Interaction$' "$portable_skill" || \
    fail "portable skill defines end-to-end latency policy"
grep -q 'semantic action span' "$contract" || \
    fail "skill UX contract permits deterministic action spans"
grep -q 'A fresh screenshot is not a phase-transition requirement' "$contract" || \
    fail "skill UX contract rejects ritual recapture"
grep -q '"scripts/app-identity.sh"' "$installer" || \
    fail "installer ships the web-app identity resolver"
grep -q '^RestartSec=250ms$' "$installer" || \
    fail "managed services recover without a two-second restart penalty"
pass "runtime contract attacks discovery, action, wait, verification, and recovery latency"

# First-use update routing must never wait on the network. The normal explicit
# update command remains free to refresh its cache.
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
[ ! -e "$update_home/network-was-called" ] || \
    fail "cached-only first-use update check never invokes curl"
[ "$elapsed_ms" -lt 500 ] || \
    fail "cached-only first-use update check returns immediately (got ${elapsed_ms}ms)"
pass "first-use update check is network-free (${elapsed_ms}ms)"

# Installed web apps backed by the same browser must keep distinct identities,
# while a normal browser launcher remains classified as browser chrome.
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
python3 - "$identity_json" <<'PY' || fail "installed web-app resolver keeps browser/PWA identity distinct"
import json
import sys
rows = json.load(open(sys.argv[1], encoding='utf-8'))
by_name = {row['display_name']: row for row in rows}
assert by_name['Google Chrome']['kind'] == 'browser'
assert by_name['Google Chrome']['standalone_web_app'] is False
assert by_name['ChatGPT']['kind'] == 'installed-web-app'
assert by_name['ChatGPT']['standalone_web_app'] is True
assert by_name['ChatGPT']['app_id'] == 'chatgpt_app'
assert by_name['Gmail']['kind'] == 'installed-web-app'
assert by_name['Gmail']['standalone_web_app'] is True
assert by_name['ChatGPT']['desktop_id'] != by_name['Gmail']['desktop_id']
PY
query_json="$TEST_TMP/query.json"
HOME="$identity_home" XDG_DATA_HOME="$identity_data" XDG_DATA_DIRS="$TEST_TMP/empty-data" \
    XDG_RUNTIME_DIR="$identity_runtime" bash "$identity" ChatGPT > "$query_json"
python3 - "$query_json" <<'PY' || fail "installed web-app resolver supports cheap name lookup"
import json
import sys
rows = json.load(open(sys.argv[1], encoding='utf-8'))
assert len(rows) == 1
assert rows[0]['display_name'] == 'ChatGPT'
PY
pass "two PWAs sharing Chrome remain distinct app targets"

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
