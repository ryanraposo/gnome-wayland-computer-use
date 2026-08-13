#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }
skill="$ROOT/SKILL.md"; installer="$ROOT/install.sh"; diagnose="$ROOT/scripts/diagnose.sh"; capture="$ROOT/scripts/capture.sh"

grep -q 'Cua Driver as the control authority' "$skill" || fail "skill does not name one control authority"
grep -q 'Never retry the same failed Cua delivery shape blindly' "$skill" || fail "skill permits ritual retry"
grep -q 'refusal by injecting raw keyboard' "$skill" || fail "skill permits raw-input refusal bypass"
! grep -q -- '--cached-only' "$skill" || fail "skill still performs task-time update housekeeping"
grep -q 'Known app means no `list_apps` / `list_windows` ceremony' "$skill" || fail "known target path still invites enumeration"
pass "agent hot path delegates mechanics to Cua"

[ ! -f "$ROOT/install-core.sh" ] || fail "runtime-patched installer architecture still exists"
[ ! -f "$ROOT/lib/checks.sh" ] || fail "obsolete shared check library still exists"
! grep -q 'sed .*install-core' "$installer" || fail "installer still patches a second installer"
grep -q 'doctor --json' "$installer" || fail "installer does not consume upstream Cua doctor"
! grep -Eq 'add_pkg ydotool|modprobe uinput|usermod .*input|CUA_DRIVER_RS_ENABLE_WAYLAND' "$installer" || fail "installer still provisions shadow input"
! grep -Eq 'ExecStart=.*serve\.sh|enable .*gnome-wayland-computer-use\.service' "$installer" || fail "installer still owns a Cua daemon"
pass "installation has one source and one control authority"

! grep -Eq 'ydotool|/dev/uinput|org\.cua\.WinRects' "$capture" || fail "observation fallback crosses authority boundary"
grep -q 'org.freedesktop.portal.Screenshot' "$capture" || fail "portal-only direct fallback missing"
pass "observation remains independent without becoming control"

mkdir -p "$TMP/home"
rc=0
HOME="$TMP/home" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE "$diagnose" --machine >"$TMP/d.json" || rc=$?
[ "$rc" -ne 0 ] || fail "degraded machine verdict exits zero"
python3 - "$TMP/d.json" <<'PY' || fail "machine verdict schema invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.diagnose.v2'; assert d['ok'] is False; assert d['next']
PY
pass "machine verdict cannot confidently lie"

for doc in README.md CAPABILITIES.md DETERMINISM.md AGENTS.md; do
    grep -qi 'Cua' "$ROOT/$doc" || fail "$doc lost Cua authority"
    ! grep -Eq 'four-plane|Input recovery' "$ROOT/$doc" || fail "$doc retains obsolete architecture"
done
pass "documentation shares the Cua-native constitution"
printf 'ok - determinism constitution complete\n'
