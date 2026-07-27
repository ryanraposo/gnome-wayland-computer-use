#!/usr/bin/env bash
# teardown.sh — uninstall gnome-wayland-computer-use stack
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/lib/checks.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

confirm() {
    $FORCE && return 0
    echo -n "  ${CK_Y}→${CK_N} $* [y/N] "
    read -r resp
    [[ "$resp" =~ ^[yY] ]]
}

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  gnome-wayland-computer-use teardown"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

removed=0

# ── 1. ydotoold.service ──
YDO="ydotoold.service"
YDO_FILE="${HOME}/.config/systemd/user/${YDO}"
if [ -f "$YDO_FILE" ]; then
    if confirm "Remove $YDO?"; then
        systemctl --user stop "$YDO" 2>/dev/null || true
        systemctl --user disable "$YDO" 2>/dev/null || true
        rm -f "$YDO_FILE"
        systemctl --user daemon-reload
        check_ok "Removed $YDO"
        ((removed++)) || true
    fi
fi

# ── 2. Revert toolkit-accessibility ──
if confirm "Revert toolkit-accessibility to false?"; then
    gsettings set org.gnome.desktop.interface toolkit-accessibility false 2>/dev/null || \
        check_info "Could not revert toolkit-accessibility (gsettings unavailable)"
    check_ok "Reverted toolkit-accessibility"
    ((removed++)) || true
fi

# ── 3. Skill files ──
SKILL_NAME="gnome-wayland-computer-use"
SKILL_DIRS=(
    "${HOME}/.agents/skills/${SKILL_NAME}"
    "${HOME}/.hermes/skills/${SKILL_NAME}"
)
for dir in "${SKILL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        if confirm "Remove skill at ${dir/$HOME/\~}?"; then
            rm -rf "$dir"
            check_ok "Removed ${dir/$HOME/\~}"
            ((removed++)) || true
        fi
    fi
done

# ── Summary ──
echo ""
if [ "$removed" -gt 0 ]; then
    check_ok "Teardown complete — $removed component(s) removed"
else
    check_info "Nothing removed"
fi

echo ""
check_info "Manual cleanup reminders:"
check_info "  User 'input' group: sudo deluser $USER input"
check_info "  ydotool package:    sudo apt remove ydotool"
