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
center_bold() { local msg="$1"; local w=$(tput cols 2>/dev/null || echo 80); printf "%$(( (w-${#msg})/2 ))s${B}%s${N}\n" "" "$msg"; }


# ── Parse args ──────────────────────────────────────────────────────────
FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# ── Install skill ───────────────────────────────────────────────────────
install_skill() {
  local src="$SELF/SKILL.md"
  local dst="${HOME}/.agents/skills/gnome-wayland-computer-use/SKILL.md"
  mkdir -p "$(dirname "$dst")"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    ok "Skill installed → ${dst/$HOME/\~}"
  elif command -v curl &>/dev/null; then
    curl -fsSL -o "$dst" "$SELF_URL/../SKILL.md"
    ok "Skill downloaded → ${dst/$HOME/\~}"
  else
    info "No skill file bundled and curl unavailable — SKILL.md not installed"
  fi
}

# ── Install extension ───────────────────────────────────────────────────
install_extension() {
  local uuid="winrects@cua"
  local dest="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$uuid"
  local src="$SELF/extension/$uuid"

  mkdir -p "$dest"

  # Prefer bundled, fall back to download
  if [ -f "$src/extension.js" ] && [ -f "$src/metadata.json" ]; then
    cp "$src/extension.js" "$dest/extension.js"
    cp "$src/metadata.json" "$dest/metadata.json"
    ok "Extension files copied from bundle"
  elif command -v curl &>/dev/null; then
    info "Downloading from trycua/cua..."
    curl -fsSL 'https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/extension.js'   -o "$dest/extension.js"
    curl -fsSL 'https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/metadata.json' -o "$dest/metadata.json"
    ok "Extension files downloaded"
  else
    fail "No bundled files and curl unavailable"
    info "Place extension.js + metadata.json manually in: $dest"
    return 1
  fi

  # Enable via gsettings
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

# ── Environment ─────────────────────────────────────────────────────────
SESSION="${XDG_SESSION_TYPE:-$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Type 2>/dev/null | cut -d= -f2)}"
DESKTOP="${XDG_CURRENT_DESKTOP:-$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Desktop 2>/dev/null | cut -d= -f2)}"

[ "$SESSION" != "wayland" ] && { fail "Session is '$SESSION' — need Wayland"; exit 1; }
ok "Session is Wayland"
[[ "$DESKTOP" != *"GNOME"* ]] && { fail "Desktop is '$DESKTOP' — need GNOME"; exit 1; }
ok "Desktop is GNOME"
command -v gsettings &>/dev/null || { fail "gsettings not found"; exit 1; }
ok "gsettings available"

# ── Install skill (always) ───────────────────────────────────────────────
install_skill

# ── Check extension state ───────────────────────────────────────────────
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/winrects@cua"
if ! $FORCE && [ -f "$EXT_DIR/extension.js" ] && command -v gnome-extensions &>/dev/null; then
  STATE="$(gnome-extensions info winrects@cua 2>/dev/null | grep -i state || echo 'NEEDS_LOGOUT')"
  if echo "$STATE" | grep -qi active; then
    ok "Extension already installed and active"
    echo -e ""
    echo -e "     ${B}Remember:${N}"
    echo -e "               log out then back in."
    echo -e ""
    echo -e "     ${B}Test:${N}"
    echo -e "               gdbus introspect --session --dest org.cua.WinRects --object-path /org/cua/WinRects"
    echo -e "
     ▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"
    exit 0
  fi
fi

install_extension

echo ""
center_bold "Remember: log out then back in."
echo ""
echo -e "  ${Y}Verify:${N}  gnome-extensions info winrects@cua"
echo -e "             gdbus introspect --session --dest org.cua.WinRects --object-path /org/cua/WinRects"
echo ""
echo -e "
     ▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"
