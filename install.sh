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

# ── Fix Hermes systemd env vars ─────────────────────────────────────────
fix_hermes_service_env() {
  local unit="hermes-webui.service"
  local dropin_dir="${HOME}/.config/systemd/user/${unit}.d"

  if ! systemctl --user --type service list-units --all 2>/dev/null | grep -q "$unit"; then
    info "Hermes systemd service not found — skipping env fix"
    return 0
  fi

  # Check if cua-driver already has the vars
  local pid
  pid="$(pgrep -x cua-driver | head -1)"
  if [ -n "$pid" ]; then
    if tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q "CUA_DRIVER_RS_ENABLE_WAYLAND=1"; then
      ok "cua-driver already has Wayland env vars"
      return 0
    fi
  fi

  info "Hermes systemd service detected — checking env var fix..."
  if [ -f "$dropin_dir/wayland-env.conf" ]; then
    ok "Systemd drop-in already exists"
  else
    mkdir -p "$dropin_dir"
    cat > "$dropin_dir/wayland-env.conf" << 'EOF'
[Service]
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=ubuntu:GNOME
Environment=WAYLAND_DISPLAY=wayland-0
Environment=DISPLAY=:0
Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1
EOF
    ok "Created systemd drop-in → ${dropin_dir/$HOME/\~}/wayland-env.conf"
    systemctl --user daemon-reload
    info "Restarting Hermes service..."
    systemctl --user restart "$unit"
    sleep 3
    ok "Hermes restarted with Wayland env vars"
  fi
}

# ── Check cua-driver version ────────────────────────────────────────────
check_cua_driver() {
  if ! command -v cua-driver &>/dev/null; then
    info "cua-driver not found — install via https://github.com/trycua/cua"
    return 0
  fi

  local ver
  ver="$(cua-driver --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
  if [ -z "$ver" ]; then
    info "Could not determine cua-driver version"
    return 0
  fi

  # Compare major.minor
  local major="${ver%%.*}"
  local rest="${ver#*.}"
  local minor="${rest%%.*}"

  if [ "$major" -eq 0 ] && [ "$minor" -lt 12 ]; then
    info "cua-driver v$ver — v0.12.6+ required for Wayland shell-helper support"
    info "Update: cua-driver update --apply"
    if command -v curl &>/dev/null; then
      info "Or: curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/install.sh | bash"
    fi
  else
    ok "cua-driver v$ver"
  fi
}

# ── Final verification ───────────────────────────────────────────────────
verify_full_stack() {
  echo ""
  center_bold "--- Verification ---"
  echo ""

  # Extension
  if command -v gnome-extensions &>/dev/null; then
    local ext_state
    ext_state="$(gnome-extensions info winrects@cua 2>/dev/null | grep -i state || true)"
    if echo "$ext_state" | grep -qi active; then
      ok "Extension: ACTIVE"
    else
      info "Extension: $ext_state (log out/in if needed)"
    fi
  fi

  # D-Bus
  if gdbus introspect --session --dest org.cua.WinRects --object-path /org/cua/WinRects 2>/dev/null | grep -q "interface org.cua.WinRects"; then
    ok "D-Bus org.cua.WinRects: alive"
  else
    info "D-Bus org.cua.WinRects: not found (log out/in?)"
  fi

  # cua-driver env
  local pid
  pid="$(pgrep -x cua-driver | head -1)"
  if [ -n "$pid" ]; then
    ok "cua-driver: running (PID $pid)"
    local missing=false
    for v in WAYLAND_DISPLAY XDG_SESSION_TYPE CUA_DRIVER_RS_ENABLE_WAYLAND; do
      if ! tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -q "^${v}="; then
        fail "cua-driver missing env: $v"
        missing=true
      fi
    done
    if ! $missing; then
      ok "cua-driver env: all Wayland vars present"
    fi
  else
    info "cua-driver: not running (will start when Hermes calls computer_use)"
  fi

  echo ""
  echo -e "  ${Y}Next step:${N} test capture in Hermes via:"
  echo -e "    computer_use(action=\"capture\", mode=\"som\")"
  echo ""
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

# ── Fix Hermes systemd env (always) ──────────────────────────────────────
fix_hermes_service_env

# ── Check cua-driver version (always) ────────────────────────────────────
check_cua_driver

# ── Check extension state ───────────────────────────────────────────────
EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/winrects@cua"
if ! $FORCE && [ -f "$EXT_DIR/extension.js" ] && command -v gnome-extensions &>/dev/null; then
  STATE="$(gnome-extensions info winrects@cua 2>/dev/null | grep -i state || echo 'NEEDS_LOGOUT')"
  if echo "$STATE" | grep -qi active; then
    ok "Extension already installed and active"
    verify_full_stack
    echo ""
    echo -e "     ${B}Remember:${N} log out then back in."
    echo -e ""
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
verify_full_stack
echo ""
echo -e "
     ▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"
