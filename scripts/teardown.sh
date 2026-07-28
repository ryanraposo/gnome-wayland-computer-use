#!/usr/bin/env bash
# teardown.sh — uninstall gnome-wayland-computer-use stack
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091  # Resolved from the installed bundle at runtime.
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

# ── 1. Hermes computer_use service ──
CUA_SERVICE="gnome-wayland-computer-use.service"
CUA_FILE="${HOME}/.config/systemd/user/${CUA_SERVICE}"
if [ -f "$CUA_FILE" ]; then
    if confirm "Remove $CUA_SERVICE?"; then
        systemctl --user disable --now "$CUA_SERVICE" 2>/dev/null || true
        rm -f "$CUA_FILE"
        systemctl --user daemon-reload
        check_ok "Removed $CUA_SERVICE"
        ((removed++)) || true
    fi
fi

# ── 2. uinput access rule ──
UDEV_RULE="/etc/udev/rules.d/80-gnome-wayland-computer-use.rules"
if [ -f "$UDEV_RULE" ]; then
    if confirm "Remove $UDEV_RULE?"; then
        sudo rm -f "$UDEV_RULE"
        sudo udevadm control --reload-rules 2>/dev/null || true
        check_ok "Removed $UDEV_RULE"
        ((removed++)) || true
    fi
fi

# ── 3. ydotoold.service ──
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

# ── 4. Revert toolkit-accessibility ──
if confirm "Revert toolkit-accessibility to false?"; then
    gsettings set org.gnome.desktop.interface toolkit-accessibility false 2>/dev/null || \
        check_info "Could not revert toolkit-accessibility (gsettings unavailable)"
    check_ok "Reverted toolkit-accessibility"
    ((removed++)) || true
fi

# ── 5. GNOME Shell desktop-capture extension ──
CAPTURE_EXTENSION_UUID="desktop-capture@gnome-wayland-computer-use"
CAPTURE_EXTENSION_DIR="${HOME}/.local/share/gnome-shell/extensions/${CAPTURE_EXTENSION_UUID}"
if [ -d "$CAPTURE_EXTENSION_DIR" ]; then
    if confirm "Remove GNOME Shell extension $CAPTURE_EXTENSION_UUID?"; then
        gnome-extensions disable "$CAPTURE_EXTENSION_UUID" 2>/dev/null || true
        rm -rf "$CAPTURE_EXTENSION_DIR"
        check_ok "Removed $CAPTURE_EXTENSION_UUID"
        ((removed++)) || true
    fi
fi

# ── 6. Skill files ──
SKILL_NAME="gnome-wayland-computer-use"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
SKILL_DIRS=(
    "${HOME}/.agents/skills/${SKILL_NAME}"
    "${HERMES_HOME}/skills/computer-use"
    "${HERMES_HOME}/skills/${SKILL_NAME}"
)
for dir in "${SKILL_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        if [ "$dir" = "${HERMES_HOME}/skills/computer-use" ] &&
           [ ! -f "$dir/.gnome-wayland-computer-use-managed" ]; then
            check_info "Keeping user-managed skill at ${dir/$HOME/\~}"
            continue
        fi
        if confirm "Remove skill at ${dir/$HOME/\~}?"; then
            rm -rf "$dir"
            check_ok "Removed ${dir/$HOME/\~}"
            ((removed++)) || true
        fi
    fi
done

# ── 7. Restore skills archived by the installer ──
BACKUP_ROOT="${HERMES_HOME}/backups/gnome-wayland-computer-use"
BACKUP_MANIFEST="${BACKUP_ROOT}/manifest.tsv"
if [ -f "$BACKUP_MANIFEST" ]; then
    remaining_manifest="${BACKUP_MANIFEST}.remaining.$$"
    : > "$remaining_manifest"
    while IFS=$'\t' read -r original backup; do
        [ -n "$original" ] && [ -n "$backup" ] || continue
        if [ ! -d "$backup" ]; then
            continue
        fi
        if [ -e "$original" ]; then
            check_info "Keeping archived skill because ${original/$HOME/\~} is occupied"
            printf '%s\t%s\n' "$original" "$backup" >> "$remaining_manifest"
        elif confirm "Restore archived skill to ${original/$HOME/\~}?"; then
            mkdir -p "$(dirname "$original")"
            mv "$backup" "$original"
            check_ok "Restored ${original/$HOME/\~}"
            ((removed++)) || true
        else
            printf '%s\t%s\n' "$original" "$backup" >> "$remaining_manifest"
        fi
    done < "$BACKUP_MANIFEST"
    if [ -s "$remaining_manifest" ]; then
        mv "$remaining_manifest" "$BACKUP_MANIFEST"
    else
        rm -f "$remaining_manifest" "$BACKUP_MANIFEST"
    fi
fi

# ── 8. Remove the always-loaded Hermes routing block ──
SOUL_FILE="${HERMES_HOME}/SOUL.md"
SOUL_START="<!-- gnome-wayland-computer-use:start -->"
SOUL_END="<!-- gnome-wayland-computer-use:end -->"
SOUL_CREATED_MARKER="${BACKUP_ROOT}/soul-created-by-installer"
if [ -f "$SOUL_FILE" ] && grep -Fxq "$SOUL_START" "$SOUL_FILE"; then
    if confirm "Remove managed desktop-capture routing from ${SOUL_FILE/$HOME/\~}?"; then
        clean_soul=$(mktemp "${SOUL_FILE}.clean.XXXXXX")
        awk -v start="$SOUL_START" -v end="$SOUL_END" '
            $0 == start { managed = 1; next }
            $0 == end { managed = 0; next }
            !managed { print }
        ' "$SOUL_FILE" > "$clean_soul"
        if [ -f "$SOUL_CREATED_MARKER" ] &&
           ! grep -q '[^[:space:]]' "$clean_soul"; then
            rm -f "$clean_soul" "$SOUL_FILE" "$SOUL_CREATED_MARKER"
        else
            chmod 600 "$clean_soul"
            mv "$clean_soul" "$SOUL_FILE"
            rm -f "$SOUL_CREATED_MARKER"
        fi
        check_ok "Removed managed Hermes routing"
        ((removed++)) || true
    fi
fi

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
