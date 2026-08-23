#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

MIGRATOR="$ROOT/scripts/migrate-main.sh"
INSTALLER="$ROOT/install.sh"
UNINSTALLER="$ROOT/uninstall.sh"

# Recreate the concrete surfaces written by published main 2.2.0.
HOME_A="$TMP/home-a"
HERMES_A="$HOME_A/.hermes"
STATE_A="$TMP/state-a/gnome-wayland-computer-use"
BIN="$TMP/bin"
RULE="$TMP/80-gnome-wayland-computer-use.rules"
mkdir -p \
  "$HOME_A/.agents/skills/gnome-wayland-computer-use" \
  "$HOME_A/.config/systemd/user" \
  "$HOME_A/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use" \
  "$HERMES_A/skills/gnome-wayland-computer-use" \
  "$HERMES_A/backups/gnome-wayland-computer-use" \
  "$BIN"
printf '2.2.0\n' >"$HOME_A/.agents/skills/gnome-wayland-computer-use/VERSION"
: >"$HERMES_A/skills/gnome-wayland-computer-use/.gnome-wayland-computer-use-managed"
cat >"$HOME_A/.config/systemd/user/gnome-wayland-computer-use.service" <<'EOF'
[Unit]
Description=cua-driver backend for GNOME Wayland computer use
[Service]
ExecStart=%h/.agents/skills/gnome-wayland-computer-use/scripts/serve.sh
EOF
cat >"$HOME_A/.config/systemd/user/ydotoold.service" <<'EOF'
[Unit]
Description=ydotool uinput daemon
[Service]
ExecStart=/usr/bin/env ydotoold
EOF
printf '%s\n' 'KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"' >"$RULE"
printf '%s\n' '{"uuid":"desktop-capture@gnome-wayland-computer-use"}' >"$HOME_A/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use/metadata.json"
cat >"$HERMES_A/SOUL.md" <<'EOF'
user text before
<!-- gnome-wayland-computer-use:start -->
old always-loaded desktop capture routing
<!-- gnome-wayland-computer-use:end -->
user text after
EOF
: >"$HERMES_A/backups/gnome-wayland-computer-use/soul-created-by-installer"

cat >"$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$BIN/gnome-extensions" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$BIN/udevadm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$BIN/pkexec" <<'EOF'
#!/usr/bin/env bash
exec "$@"
EOF
chmod +x "$BIN/"*

HOME="$HOME_A" HERMES_HOME="$HERMES_A" XDG_STATE_HOME="$TMP/state-a" \
  GWCU_UDEV_RULE_PATH="$RULE" PATH="$BIN:/usr/bin:/bin" \
  bash "$MIGRATOR" --repair --quiet

[ ! -e "$HOME_A/.config/systemd/user/gnome-wayland-computer-use.service" ] || fail "old cua service survived migration"
[ ! -e "$HOME_A/.config/systemd/user/ydotoold.service" ] || fail "old ydotool service survived migration"
[ ! -e "$RULE" ] || fail "old uinput rule survived migration"
[ ! -e "$HOME_A/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use" ] || fail "old desktop-capture extension survived migration"
[ ! -e "$HERMES_A/skills/gnome-wayland-computer-use" ] || fail "old Hermes skill alias survived migration"
grep -Fxq 'user text before' "$HERMES_A/SOUL.md" || fail "migration damaged user SOUL prefix"
grep -Fxq 'user text after' "$HERMES_A/SOUL.md" || fail "migration damaged user SOUL suffix"
! grep -Fq 'gnome-wayland-computer-use:start' "$HERMES_A/SOUL.md" || fail "old SOUL routing survived migration"
[ -f "$HOME_A/.agents/skills/gnome-wayland-computer-use/VERSION" ] || fail "migration removed primary bundle before installer could replace it"
[ "$(cat "$STATE_A/repaired-main-version")" = 2.2.0 ] || fail "migration did not record repaired main generation"
HOME="$HOME_A" HERMES_HOME="$HERMES_A" XDG_STATE_HOME="$TMP/state-a" \
  GWCU_UDEV_RULE_PATH="$RULE" PATH="$BIN:/usr/bin:/bin" \
  bash "$MIGRATOR" --verify --quiet
pass "published main 2.2 artifacts migrate in place without touching user SOUL content"

# The installer must repair before it starts the new Cua/portal generation.
migrate_line=$(grep -n 'get_file scripts/migrate-main.sh "$MIGRATOR"' "$INSTALLER" | head -1 | cut -d: -f1)
cua_line=$(grep -n 'Installing / qualifying pinned Cua Driver' "$INSTALLER" | head -1 | cut -d: -f1)
[ -n "$migrate_line" ] && [ -n "$cua_line" ] && [ "$migrate_line" -lt "$cua_line" ] || fail "installer migrates old main too late"
grep -Fq 'scripts/migrate-main.sh' "$INSTALLER" || fail "installer does not ship migrator"
grep -Fq 'Verifying published-main repair and single control plane' "$INSTALLER" || fail "installer does not verify migration"
pass "upgrade repair runs before new Cua and is verified afterward"

# Under the public curl-pipe path, an installed 2.2 teardown must never win.
HOME_B="$TMP/home-b"
mkdir -p "$HOME_B/.agents/skills/gnome-wayland-computer-use/scripts" "$TMP/bin-b"
printf '2.2.0\n' >"$HOME_B/.agents/skills/gnome-wayland-computer-use/VERSION"
cat >"$HOME_B/.agents/skills/gnome-wayland-computer-use/scripts/teardown.sh" <<'EOF'
#!/usr/bin/env bash
touch "$STALE_CALLED"
EOF
chmod +x "$HOME_B/.agents/skills/gnome-wayland-computer-use/scripts/teardown.sh"
cat >"$TMP/bin-b/curl" <<'EOF'
#!/usr/bin/env bash
out=""; url=""
while [ $# -gt 0 ]; do
  case "$1" in -o) shift; out="$1";; http*) url="$1";; esac
  shift || true
done
case "$url" in
  */scripts/teardown.sh)
    cat >"$out" <<'SH'
#!/usr/bin/env bash
touch "$CURRENT_CALLED"
SH
    ;;
  */scripts/migrate-main.sh)
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$out"
    ;;
  *) exit 22;;
esac
EOF
chmod +x "$TMP/bin-b/curl"
(
  cd "$TMP"
  HOME="$HOME_B" PATH="$TMP/bin-b:/usr/bin:/bin" \
    STALE_CALLED="$TMP/stale-called" CURRENT_CALLED="$TMP/current-called" \
    bash -s -- <"$UNINSTALLER"
)
[ -e "$TMP/current-called" ] || fail "public uninstaller did not use current teardown"
[ ! -e "$TMP/stale-called" ] || fail "public uninstaller executed stale 2.2 teardown"
pass "public uninstall bypasses stale installed teardown logic"
