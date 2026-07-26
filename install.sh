#!/usr/bin/env bash
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; N='\033[0m'
ok()  { echo -e "  ${G}✓${N} $1"; }
info(){ echo -e "  ${Y}→${N} $1"; }
fail(){ echo -e "  ${R}✗${N} $1"; }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

install_skill() {
  local src="$SELF/SKILL.md"
  local dst="${HOME}/.agents/skills/gnome-wayland-computer-use/SKILL.md"
  mkdir -p "$(dirname "$dst")"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    ok "Skill installed"
  elif command -v curl &>/dev/null; then
    curl -fsSL -o "$dst" "https://ryanraposo.github.io/gnome-wayland-computer-use/SKILL.md"
    ok "Skill downloaded"
  else
    info "No skill file bundled and curl unavailable"
  fi
}

install_extension() {
  local uuid="winrects@cua"
  local dest="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$uuid"
  local src="$SELF/extension/$uuid"

  mkdir -p "$dest"

  if [ -f "$src/extension.js" ] && [ -f "$src/metadata.json" ]; then
    cp "$src/extension.js" "$dest/extension.js"
    cp "$src/metadata.json" "$dest/metadata.json"
    ok "Extension files copied"
  elif command -v curl &>/dev/null; then
    curl -fsSL -o "$dest/extension.js"   'https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/extension.js'
    curl -fsSL -o "$dest/metadata.json" 'https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/metadata.json'
    ok "Extension files downloaded"
  else
    fail "No bundled files and curl unavailable"
    return 1
  fi

  local cur
  cur="$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo '@as []')"
  python3 - "$cur" "$uuid" <<'PY'
import ast, subprocess, sys
try:    lst = ast.literal_eval(sys.argv[1])
except: lst = []
if sys.argv[2] not in lst: lst.append(sys.argv[2])
subprocess.run(["gsettings","set","org.gnome.shell","enabled-extensions",str(lst)], check=True)
PY
  ok "Extension enabled in gsettings"
}

fix_hermes_service_env() {
  local unit="hermes-webui.service"
  local dropin_dir="${HOME}/.config/systemd/user/${unit}.d"

  if ! systemctl --user --type service list-units --all 2>/dev/null | grep -q "$unit"; then
    return 0
  fi

  local pid
  pid="$(pgrep -x cua-driver | head -1)"
  if [ -n "$pid" ] && tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q "CUA_DRIVER_RS_ENABLE_WAYLAND=1"; then
    return 0
  fi

  if [ ! -f "$dropin_dir/wayland-env.conf" ]; then
    mkdir -p "$dropin_dir"
    cat > "$dropin_dir/wayland-env.conf" << 'EOF'
[Service]
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=ubuntu:GNOME
Environment=WAYLAND_DISPLAY=wayland-0
Environment=DISPLAY=:0
Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1
EOF
    systemctl --user daemon-reload
    systemctl --user restart "$unit"
    sleep 3
    ok "Hermes systemd env fixed"
  fi
}

check_cua_driver() {
  if ! command -v cua-driver &>/dev/null; then
    return 0
  fi

  local ver
  ver="$(cua-driver --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
  if [ -z "$ver" ]; then
    return 0
  fi

  local major="${ver%%.*}"
  local rest="${ver#*.}"
  local minor="${rest%%.*}"

  if [ "$major" -eq 0 ] && [ "$minor" -lt 12 ]; then
    info "cua-driver v$ver — v0.12.6+ recommended, run: cua-driver update --apply"
  fi
}

SESSION="${XDG_SESSION_TYPE:-$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Type 2>/dev/null | cut -d= -f2)}"
DESKTOP="${XDG_CURRENT_DESKTOP:-$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Desktop 2>/dev/null | cut -d= -f2)}"

[ "$SESSION" != "wayland" ] && { fail "Session is '$SESSION' — need Wayland"; exit 1; }
[[ "$DESKTOP" != *"GNOME"* ]] && { fail "Desktop is '$DESKTOP' — need GNOME"; exit 1; }

install_skill
fix_hermes_service_env
check_cua_driver

EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/winrects@cua"
if ! $FORCE && [ -f "$EXT_DIR/extension.js" ] && command -v gnome-extensions &>/dev/null; then
  STATE="$(gnome-extensions info winrects@cua 2>/dev/null | grep -i state || echo 'NEEDS_LOGOUT')"
  if echo "$STATE" | grep -qi active; then
    ok "Extension installed and active"
    echo -e "\n  ${Y}Next:${N} computer_use(action=\"capture\", mode=\"som\")"
    exit 0
  fi
fi

install_extension
echo ""
info "Done. Log out then back in to activate."
echo -e "  ${Y}Verify:${N} gnome-extensions info winrects@cua"
echo ""
