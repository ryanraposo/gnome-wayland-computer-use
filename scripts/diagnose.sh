#!/usr/bin/env bash
# diagnose.sh — full-stack diagnostic for gnome-wayland-computer-use
# Checks: display server, extension, D-Bus, cua-driver env/version, capture
set -euo pipefail

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'; B='\033[1m'; N='\033[0m'
ok()   { echo -e "  ${G}✓${N} $1"; }
info() { echo -e "  ${Y}→${N} $1"; }
fail() { echo -e "  ${R}✗${N} $1"; }
hr()   { echo "────────────────────────────────────────"; }

SCORE=0
TOTAL=0
pass() { ((SCORE++)) || true; ((TOTAL++)) || true; }
xfail(){ ((TOTAL++)) || true; }

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  gnome-wayland-computer-use diagnose"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ── 1. Display server ──────────────────────────────────────────────────
echo "── 1. Display server"; hr

SESSION_TYPE="${XDG_SESSION_TYPE:-$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Type 2>/dev/null | cut -d= -f2)}"
echo "   XDG_SESSION_TYPE: ${SESSION_TYPE:-<unset>}"
echo "   DISPLAY:          ${DISPLAY:-<unset>}"
echo "   WAYLAND_DISPLAY:  ${WAYLAND_DISPLAY:-<unset>}"

if [ "$SESSION_TYPE" = "wayland" ]; then
  ok "Session is Wayland"; pass
else
  fail "Session is '$SESSION_TYPE' — expected 'wayland'"
  xfail
fi

if pgrep -x Xwayland &>/dev/null; then
  ok "XWayland running"; pass
else
  info "XWayland not running (expected on pure Wayland)"; xfail
fi

if pgrep -x gnome-shell &>/dev/null; then
  ok "GNOME Shell running"; pass
else
  fail "GNOME Shell not running"; xfail
fi

echo ""

# ── 2. Extension ────────────────────────────────────────────────────────
echo "── 2. Extension"; hr

EXT_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/winrects@cua"
if [ -f "$EXT_DIR/extension.js" ] && [ -f "$EXT_DIR/metadata.json" ]; then
  ok "Extension files present at ${EXT_DIR/$HOME/\~}"; pass
else
  fail "Extension files missing"; xfail
fi

if command -v gnome-extensions &>/dev/null; then
  EXT_STATE="$(gnome-extensions info winrects@cua 2>/dev/null | grep -i state || echo 'UNKNOWN')"
  echo "   gnome-extensions state: $EXT_STATE"
  if echo "$EXT_STATE" | grep -qi active; then
    ok "Extension ACTIVE"; pass
  else
    info "Extension not ACTIVE (log out/in required)"; xfail
  fi
else
  info "gnome-extensions CLI not available"; xfail
fi

echo ""

# ── 3. D-Bus interface ─────────────────────────────────────────────────
echo "── 3. D-Bus interface"; hr

if gdbus introspect --session --dest org.cua.WinRects --object-path /org/cua/WinRects 2>/dev/null | grep -q "interface org.cua.WinRects"; then
  ok "org.cua.WinRects D-Bus interface alive"; pass
  echo "   Methods available:"
  gdbus introspect --session --dest org.cua.WinRects --object-path /org/cua/WinRects 2>/dev/null | grep -E "^\s+(GetRects|Capture|Activate|MoveCursor|ClickPulse)" | sed 's/^/     /'

  # Test GetRects
  RECTS="$(gdbus call --session --dest org.cua.WinRects --object-path /org/cua/WinRects --method org.cua.WinRects.GetRects 2>&1)"
  if echo "$RECTS" | grep -q '"id"'; then
    local count
    count="$(echo "$RECTS" | grep -o '"id"' | wc -l)"
    ok "GetRects: $count window(s) reported"; pass
  else
    info "GetRects: no windows or unexpected format"; xfail
  fi

  # Test Capture
  CAPTURE="$(gdbus call --session --dest org.cua.WinRects --object-path /org/cua/WinRects --method org.cua.WinRects.Capture 2>&1 | head -c 60)"
  if echo "$CAPTURE" | grep -qi "iVBORw0KGgo"; then
    ok "Capture: valid PNG returned"; pass
  else
    info "Capture: unexpected output (may still work)"; xfail
  fi
else
  fail "org.cua.WinRects D-Bus interface NOT FOUND"; xfail
fi

echo ""

# ── 4. cua-driver process ──────────────────────────────────────────────
echo "── 4. cua-driver"; hr

PID="$(pgrep -x cua-driver | head -1)"
if [ -n "$PID" ]; then
  ok "cua-driver running (PID $PID)"; pass

  VER="$(cua-driver --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
  echo "   Version: ${VER:-unknown}"

  if [ -n "$VER" ]; then
    local major="${VER%%.*}"
    local rest="${VER#*.}"
    local minor="${rest%%.*}"
    if [ "$major" -gt 0 ] || [ "$minor" -ge 12 ]; then
      ok "cua-driver v$VER (>= 0.12.6)"; pass
    else
      info "cua-driver v$VER — v0.12.6+ recommended for Wayland shell-helper"; xfail
    fi
  fi

  echo "   Environment:"
  local missing=0
  for v in WAYLAND_DISPLAY XDG_SESSION_TYPE CUA_DRIVER_RS_ENABLE_WAYLAND; do
    val="$(tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | grep "^${v}=" || true)"
    if [ -n "$val" ]; then
      echo "     ✓ ${val}"
    else
      echo "     ✗ ${v}=<missing>"
      ((missing++)) || true
    fi
  done
  if [ "$missing" -eq 0 ]; then
    ok "All required env vars present"; pass
  else
    fail "$missing required env var(s) missing — run fix_hermes_env below"; xfail
  fi
else
  info "cua-driver not running (will spawn on first computer_use call)"; xfail
fi

echo ""

# ── 5. Summary ─────────────────────────────────────────────────────────
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Result: $SCORE / $TOTAL checks passed"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [ "$SCORE" -ne "$TOTAL" ]; then
  echo "  ${Y}Issues found. Common fixes:${N}"
  echo ""
  if ! command -v gnome-extensions &>/dev/null || ! gnome-extensions info winrects@cua 2>/dev/null | grep -qi active; then
    echo "  1. Run install.sh to install winrects@cua:"
    echo "     curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash"
    echo ""
  fi
  if ! tr '\0' '\n' < "/proc/${PID:-0}/environ" 2>/dev/null | grep -q "CUA_DRIVER_RS_ENABLE_WAYLAND=1"; then
    echo "  2. Fix Hermes systemd service env vars:"
    echo "     mkdir -p ~/.config/systemd/user/hermes-webui.service.d"
    echo '     cat > ~/.config/systemd/user/hermes-webui.service.d/wayland-env.conf << '\''EOF'\'''
    echo '     [Service]'
    echo '     Environment=XDG_SESSION_TYPE=wayland'
    echo '     Environment=XDG_CURRENT_DESKTOP=ubuntu:GNOME'
    echo '     Environment=WAYLAND_DISPLAY=wayland-0'
    echo '     Environment=DISPLAY=:0'
    echo '     Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1'
    echo '     EOF'
    echo "     systemctl --user daemon-reload"
    echo "     systemctl --user restart hermes-webui.service"
    echo ""
  fi
  if ! command -v cua-driver &>/dev/null || ! cua-driver --version 2>&1 | grep -qP '([1-9]\d*\.|0\.([1-9]\d|[1-9])\.)'; then
    echo "  3. Update cua-driver to v0.12.6+:"
    echo "     cua-driver update --apply"
    echo "     # or: curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/install.sh | bash"
    echo ""
  fi
  echo "  ${Y}Then re-run this diagnostic.${N}"
else
  echo "  ${G}All checks passed! computer_use should work.${N}"
  echo ""

fi
echo ""
