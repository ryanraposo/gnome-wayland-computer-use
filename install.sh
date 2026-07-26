#!/usr/bin/env bash

echo -e "
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"

set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)"
SELF_URL="https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh"

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1m'; N='\033[0m'
ok()  { echo -e "  ${G}✓${N} $1"; }
info(){ echo -e "  ${Y}→${N} $1"; }
fail(){ echo -e "  ${R}✗${N} $1"; }

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# ── Prerequisites ───────────────────────────────────────────────────────
SESSION="${XDG_SESSION_TYPE:-$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Type 2>/dev/null | cut -d= -f2)}"
DESKTOP="${XDG_CURRENT_DESKTOP:-$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Desktop 2>/dev/null | cut -d= -f2)}"

[ "$SESSION" != "wayland" ] && { fail "Session is '$SESSION' — need Wayland"; exit 1; }
ok "Session is Wayland"
[[ "$DESKTOP" != *"GNOME"* ]] && { fail "Desktop is '$DESKTOP' — need GNOME"; exit 1; }
ok "Desktop is GNOME"
command -v gsettings &>/dev/null || { fail "gsettings not found"; exit 1; }

# ── Install skill ───────────────────────────────────────────────────────
install_skill() {
  local src="$SELF/SKILL.md"
  local name="gnome-wayland-computer-use"

  # Install to opencode's skill directory
  local dst="${HOME}/.agents/skills/${name}/SKILL.md"
  mkdir -p "$(dirname "$dst")"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    ok "Skill installed → ${dst/$HOME/\~}"
  elif command -v curl &>/dev/null; then
    curl -fsSL -o "$dst" "https://ryanraposo.github.io/gnome-wayland-computer-use/SKILL.md"
    ok "Skill downloaded → ${dst/$HOME/\~}"
  fi

  # Also install to Hermes skill directory if Hermes is present
  local hermes_dir="${HOME}/.hermes/skills"
  if [ -d "$hermes_dir" ]; then
    local hdst="${hermes_dir}/${name}/SKILL.md"
    mkdir -p "$(dirname "$hdst")"
    if [ -f "$src" ]; then
      cp "$src" "$hdst"
    else
      curl -fsSL -o "$hdst" "https://ryanraposo.github.io/gnome-wayland-computer-use/SKILL.md"
    fi
    ok "Hermes skill installed → ${hdst/$HOME/\~}"
  fi
}
install_skill

# ── Install / update cua-driver ─────────────────────────────────────────
if ! command -v cua-driver &>/dev/null; then
  info "cua-driver not found — installing..."
  curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/install.sh | bash
  ok "cua-driver installed"
elif $FORCE; then
  info "cua-driver found, --force set — running cua-driver update..."
  cua-driver update --apply 2>/dev/null || \
    curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/install.sh | bash
  ok "cua-driver updated"
else
  VER=$(cua-driver --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)
  if [ -n "$VER" ]; then
    ok "cua-driver v$VER"
  else
    ok "cua-driver found (version unknown)"
  fi
fi

# ── Fix Hermes systemd env (if applicable) ──────────────────────────────
HERMES_UNIT="hermes-webui.service"
if systemctl --user --type service list-units --all 2>/dev/null | grep -q "$HERMES_UNIT"; then
  DROPIN="${HOME}/.config/systemd/user/${HERMES_UNIT}.d/wayland-env.conf"
  if [ ! -f "$DROPIN" ]; then
    mkdir -p "$(dirname "$DROPIN")"
    cat > "$DROPIN" << 'EOF'
[Service]
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=ubuntu:GNOME
Environment=WAYLAND_DISPLAY=wayland-0
Environment=DISPLAY=:0
Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1
EOF
    systemctl --user daemon-reload
    systemctl --user restart "$HERMES_UNIT"
    sleep 2
    ok "Hermes systemd env fixed"
  else
    ok "Hermes systemd env already configured"
  fi
fi

# ── Install extension ───────────────────────────────────────────────────
install_extension() {
  local uuid="winrects@cua"
  local dest="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$uuid"
  local src="$SELF/extension/$uuid"

  mkdir -p "$dest"

  if [ -f "$src/extension.js" ] && [ -f "$src/metadata.json" ]; then
    cp "$src/extension.js" "$dest/extension.js"
    cp "$src/metadata.json" "$dest/metadata.json"
    ok "Extension files copied from repo bundle"
  elif command -v curl &>/dev/null; then
    curl -fsSL -o "$dest/extension.js" \
      'https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/extension.js'
    curl -fsSL -o "$dest/metadata.json" \
      'https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/metadata.json'
    ok "Extension files downloaded"
  else
    fail "No bundled files and curl unavailable"
    exit 1
  fi

  # Enable via gnome-extensions (activates immediately via D-Bus)
  if command -v gnome-extensions &>/dev/null; then
    gnome-extensions enable "$uuid"
    sleep 1
    STATE=$(gnome-extensions info "$uuid" 2>/dev/null | grep -i state | tr -d ' \t')
    if [ "$STATE" = "State:ACTIVE" ]; then
      ok "Extension enabled and active"
    else
      ok "Extension installed — needs GNOME Shell restart to activate"
    fi
  else
    # Fallback: gsettings directly
    cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")
    python3 - "$cur" "$uuid" << 'PY'
import ast, subprocess, sys
try:    l = ast.literal_eval(sys.argv[1])
except: l = []
if sys.argv[2] not in l: l.append(sys.argv[2])
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(l)])
PY
    ok "Extension enabled in gsettings — needs GNOME Shell restart to activate"
  fi
}

# ── Check extension state ───────────────────────────────────────────────
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/winrects@cua"
NEEDS_RESTART=false

if ! $FORCE && [ -f "$EXT_DIR/extension.js" ] && command -v gnome-extensions &>/dev/null; then
  STATE=$(gnome-extensions info winrects@cua 2>/dev/null | grep -i state || echo 'NEEDS_LOGOUT')
  if echo "$STATE" | grep -qi active; then
    ok "Extension already installed and active"
  else
    info "Extension installed but not active — enabling..."
    install_extension
    NEEDS_RESTART=true
  fi
else
  install_extension
  NEEDS_RESTART=true
fi

echo ""

if $NEEDS_RESTART; then
  echo -e "  ${Y}→ GNOME Shell restart required to activate the extension.${N}"
  echo -e "  ${Y}→ Log out and back in to activate the extension.${N}"
  echo ""
fi

echo -e "     ${B}All done. Please restart GNOME Shell or log out/in.${N}"
echo ""
echo -e "  ${Y}Verify:${N} gnome-extensions info winrects@cua"
echo -e "
     ▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"
