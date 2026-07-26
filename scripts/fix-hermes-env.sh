#!/usr/bin/env bash
# fix-hermes-env.sh — add Wayland env vars to hermes-webui systemd service
set -euo pipefail

UNIT="hermes-webui.service"
DROPIN_DIR="${HOME}/.config/systemd/user/${UNIT}.d"
DROPIN="${DROPIN_DIR}/wayland-env.conf"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $1"; }
info() { echo -e "  ${Y}→${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }

# Check if Hermes systemd service exists
if ! systemctl --user --type service list-units --all 2>/dev/null | grep -q "$UNIT"; then
  fail "Hermes systemd service ($UNIT) not found"
  info "This fix is only needed when Hermes runs as a systemd user service"
  exit 1
fi
ok "Hermes systemd service found"

# Check if drop-in already exists
if [ -f "$DROPIN" ]; then
  ok "Drop-in already exists at ${DROPIN/$HOME/\~}"
  info "Contents:"
  sed 's/^/  /' "$DROPIN"
  echo ""

  # Check if cua-driver actually has the vars now
  PID="$(pgrep -x cua-driver | head -1)"
  if [ -n "$PID" ] && tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | grep -q "CUA_DRIVER_RS_ENABLE_WAYLAND=1"; then
    ok "cua-driver already has Wayland env vars — no action needed"
    exit 0
  fi

  info "cua-driver still missing vars — restarting service..."
fi

# Create drop-in
mkdir -p "$DROPIN_DIR"
cat > "$DROPIN" << 'EOF'
[Service]
# Required for cua-driver to detect Wayland backend
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=ubuntu:GNOME
Environment=WAYLAND_DISPLAY=wayland-0
Environment=DISPLAY=:0
# Opt cua-driver into the Wayland shell-helper path
Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1
EOF
ok "Drop-in written to ${DROPIN/$HOME/\~}"

systemctl --user daemon-reload
ok "systemd daemon reloaded"

info "Restarting $UNIT..."
systemctl --user restart "$UNIT"
sleep 3

# Verify
PID="$(pgrep -x cua-driver | head -1)"
if [ -z "$PID" ]; then
  info "cua-driver not yet started (will spawn on first computer_use call)"
else
  ok "cua-driver running (PID $PID)"
  for v in WAYLAND_DISPLAY XDG_SESSION_TYPE CUA_DRIVER_RS_ENABLE_WAYLAND; do
    val="$(tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | grep "^${v}=" || true)"
    if [ -n "$val" ]; then
      ok "  $val"
    else
      fail "  $v=<missing>"
    fi
  done
fi

echo ""
info "Done. Test with: computer_use(action=\"capture\", mode=\"som\")"
