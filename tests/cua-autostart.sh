#!/usr/bin/env bash
# cua-autostart.sh tests — the Cua logon daemon stays standard and owned.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
passed=0
pass(){ printf 'ok - %s\n' "$1"; ((passed++)) || true; }
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }

installer="$ROOT/install.sh"
teardown="$ROOT/scripts/teardown.sh"
helper="$ROOT/scripts/cua-autostart.sh"
template="$ROOT/systemd/user/gnome-wayland-computer-use-cua-driver.service"
unit="gnome-wayland-computer-use-cua-driver.service"

bash -n "$helper" || fail "helper shell syntax"
bash "$helper" self-test >/dev/null || fail "helper render/classify/remove self-test"
pass "cua-autostart helper renders, preserves and retires its unit"

for needle in \
  '# gnome-wayland-computer-use managed unit' \
  'PartOf=graphical-session.target' \
  'ExecStart="%CUA_DRIVER_BIN%" serve' \
  'Restart=on-failure' \
  'WantedBy=graphical-session.target'
do
  grep -Fq "$needle" "$template" || fail "unit lost: $needle"
done
! grep -Eiq 'ydotool|uinput|vnc|x11' "$template" || fail "unit introduces a shadow control plane"
pass "unit is graphical-logon scoped and bound by placeholder"

grep -Fq "scripts/cua-autostart.sh" "$installer" || fail "installer omits the autostart helper"
grep -Fq "systemd/user/$unit" "$installer" || fail "installer omits the autostart unit"
grep -Fq 'ensure_cua_autostart "$UNIT_DIR"' "$installer" || fail "installer never enables the logon daemon"
grep -Fq 'is-enabled "$external"' "$installer" || fail "installer can displace an external Cua autostart"
grep -Fq 'is-active "$CUA_AUTOSTART_UNIT"' "$installer" || fail "installer does not prove the unit is active"
grep -Fq '"$CUA" status >"$STATE/cua-autostart-status.txt"' "$installer" || fail "installer does not prove daemon health"
grep -Fq 'c["autostart"]=' "$installer" || fail "ownership does not record autostart state"
grep -Fq '"cua_autostart":' "$installer" || fail "receipt does not record autostart state"
! grep -Eq 'ExecStart=.*cua-driver.*serve' "$installer" || fail "installer writes an inline shadow daemon"
pass "installer enables, proves and records the logon daemon without a shadow plane"

grep -Fq "$unit" "$teardown" || fail "teardown does not retire the logon unit"
grep -Fq "grep -Fq '# gnome-wayland-computer-use managed unit'" "$teardown" || fail "teardown is not ownership-aware"
grep -Fq 'Preserving unmanaged Cua autostart unit' "$teardown" || fail "teardown does not preserve external units"
pass "teardown removes only the GWCU-owned unit"

grep -qi 'logon daemon' "$ROOT/README.md" || fail "README lost the logon daemon contract"
grep -qi 'logon daemon' "$ROOT/index.html" || fail "Pages lost the logon daemon contract"
grep -Fq 'Cua logon:' "$installer" || fail "installer summary lost the logon daemon result"
pass "install, README and Pages agree that the logon daemon is standard"

printf 'ok - cua-autostart regression complete (%d checks)\n' "$passed"
