#!/usr/bin/env bash
# teardown.sh — uninstall managed gnome-wayland-computer-use state
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/checks.sh"

FORCE=false
[[ "${1:-}" == --force ]] && FORCE=true
confirm() {
    $FORCE && return 0
    echo -n "  ${CK_Y}→${CK_N} $* [y/N] "
    read -r resp
    [[ "$resp" =~ ^[yY] ]]
}

removed=0
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  gnome-wayland-computer-use teardown"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Hermes runtime service.
CUA_SERVICE='gnome-wayland-computer-use.service'
CUA_FILE="$HOME/.config/systemd/user/$CUA_SERVICE"
if [ -f "$CUA_FILE" ] && confirm "Remove $CUA_SERVICE?"; then
    systemctl --user disable --now "$CUA_SERVICE" 2>/dev/null || true
    rm -f "$CUA_FILE"
    systemctl --user daemon-reload
    check_ok "Removed $CUA_SERVICE"
    ((removed++)) || true
fi

# Cua WinRects is removed only when this project recorded that it caused the
# extension to be installed. Cua owns the code/protocol; this marker owns only
# our provisioning decision.
WINRECTS_UUID='winrects@cua'
WINRECTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$WINRECTS_UUID"
WINRECTS_MARKER="$STATE_DIR/cua-winrects-managed"
if [ -f "$WINRECTS_MARKER" ]; then
    if [ -d "$WINRECTS_DIR" ] && confirm "Remove Cua WinRects installed by this project?"; then
        command -v gnome-extensions &>/dev/null && gnome-extensions disable "$WINRECTS_UUID" 2>/dev/null || true
        enabled=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)
        if [ -n "$enabled" ] && command -v python3 >/dev/null 2>&1; then
            updated=$(python3 - "$enabled" "$WINRECTS_UUID" <<'PY'
import ast, sys
try:
    items = ast.literal_eval(sys.argv[1])
except Exception:
    raise SystemExit(1)
print(repr([item for item in items if item != sys.argv[2]]))
PY
) || updated=""
            [ -z "$updated" ] || gsettings set org.gnome.shell enabled-extensions "$updated" 2>/dev/null || true
        fi
        rm -rf "$WINRECTS_DIR"
        rm -f "$WINRECTS_MARKER"
        check_ok "Removed project-provisioned Cua WinRects"
        ((removed++)) || true
    elif [ ! -d "$WINRECTS_DIR" ]; then
        rm -f "$WINRECTS_MARKER"
    fi
fi

# Managed uinput rule.
UDEV_RULE='/etc/udev/rules.d/80-gnome-wayland-computer-use.rules'
if [ -f "$UDEV_RULE" ] && confirm "Remove $UDEV_RULE?"; then
    if command -v pkexec >/dev/null 2>&1; then
        pkexec rm -f "$UDEV_RULE"
        pkexec udevadm control --reload-rules 2>/dev/null || true
    else
        sudo rm -f "$UDEV_RULE"
        sudo udevadm control --reload-rules 2>/dev/null || true
    fi
    check_ok "Removed $UDEV_RULE"
    ((removed++)) || true
fi

# User-created ydotoold unit only; keep distro ydotool.service.
YDO_FILE="$HOME/.config/systemd/user/ydotoold.service"
if [ -f "$YDO_FILE" ] && confirm "Remove ydotoold.service?"; then
    systemctl --user disable --now ydotoold.service 2>/dev/null || true
    rm -f "$YDO_FILE"
    systemctl --user daemon-reload
    check_ok "Removed ydotoold.service"
    ((removed++)) || true
fi

# Revert accessibility only by explicit choice.
if confirm "Revert toolkit-accessibility to false?"; then
    gsettings set org.gnome.desktop.interface toolkit-accessibility false 2>/dev/null || true
    check_ok "Reverted toolkit-accessibility"
    ((removed++)) || true
fi

# Obsolete project capture extension is managed migration debris: always remove
# it if found. It is never a user-owned dependency in 2.3.
LEGACY_UUID='desktop-capture@gnome-wayland-computer-use'
LEGACY_DIR="$HOME/.local/share/gnome-shell/extensions/$LEGACY_UUID"
if [ -d "$LEGACY_DIR" ]; then
    command -v gnome-extensions &>/dev/null && gnome-extensions disable "$LEGACY_UUID" 2>/dev/null || true
    rm -rf "$LEGACY_DIR"
    check_ok "Removed obsolete project capture extension"
    ((removed++)) || true
fi

# Portal restore state belongs to this project and can be revoked independently.
if [ -e "$STATE_DIR/screencast-restore-token" ] && confirm "Remove cached ScreenCast restore token?"; then
    rm -f "$STATE_DIR/screencast-restore-token"
    check_ok "Removed cached ScreenCast restore token"
    ((removed++)) || true
fi
rmdir "$STATE_DIR" 2>/dev/null || true

# Skill files.
SKILL_NAME='gnome-wayland-computer-use'
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
SKILL_DIRS=(
    "$HOME/.agents/skills/$SKILL_NAME"
    "$HERMES_HOME/skills/computer-use"
    "$HERMES_HOME/skills/$SKILL_NAME"
)
for dir in "${SKILL_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    if [ "$dir" = "$HERMES_HOME/skills/computer-use" ] && [ ! -f "$dir/.gnome-wayland-computer-use-managed" ]; then
        check_info "Keeping user-managed skill at ${dir/$HOME/\~}"
        continue
    fi
    if confirm "Remove skill at ${dir/$HOME/\~}?"; then
        rm -rf "$dir"
        check_ok "Removed ${dir/$HOME/\~}"
        ((removed++)) || true
    fi
done

# Restore archived Hermes skills.
BACKUP_ROOT="$HERMES_HOME/backups/gnome-wayland-computer-use"
BACKUP_MANIFEST="$BACKUP_ROOT/manifest.tsv"
if [ -f "$BACKUP_MANIFEST" ]; then
    remaining="$BACKUP_MANIFEST.remaining.$$"
    : > "$remaining"
    while IFS=$'\t' read -r original backup; do
        [ -n "$original" ] && [ -d "$backup" ] || continue
        if [ -e "$original" ]; then
            printf '%s\t%s\n' "$original" "$backup" >> "$remaining"
        elif confirm "Restore archived skill to ${original/$HOME/\~}?"; then
            mkdir -p "$(dirname "$original")"
            mv "$backup" "$original"
            check_ok "Restored ${original/$HOME/\~}"
            ((removed++)) || true
        else
            printf '%s\t%s\n' "$original" "$backup" >> "$remaining"
        fi
    done < "$BACKUP_MANIFEST"
    if [ -s "$remaining" ]; then mv "$remaining" "$BACKUP_MANIFEST"; else rm -f "$remaining" "$BACKUP_MANIFEST"; fi
fi

# Managed Hermes SOUL block.
SOUL_FILE="$HERMES_HOME/SOUL.md"
SOUL_START='<!-- gnome-wayland-computer-use:start -->'
SOUL_END='<!-- gnome-wayland-computer-use:end -->'
SOUL_CREATED_MARKER="$BACKUP_ROOT/soul-created-by-installer"
if [ -f "$SOUL_FILE" ] && grep -Fxq "$SOUL_START" "$SOUL_FILE" && confirm "Remove managed computer-use routing from ${SOUL_FILE/$HOME/\~}?"; then
    clean=$(mktemp "${SOUL_FILE}.clean.XXXXXX")
    awk -v start="$SOUL_START" -v end="$SOUL_END" '
        $0 == start { managed = 1; next }
        $0 == end { managed = 0; next }
        !managed { print }
    ' "$SOUL_FILE" > "$clean"
    if [ -f "$SOUL_CREATED_MARKER" ] && ! grep -q '[^[:space:]]' "$clean"; then
        rm -f "$clean" "$SOUL_FILE" "$SOUL_CREATED_MARKER"
    else
        chmod 600 "$clean"
        mv "$clean" "$SOUL_FILE"
        rm -f "$SOUL_CREATED_MARKER"
    fi
    check_ok "Removed managed Hermes routing"
    ((removed++)) || true
fi

echo ""
if [ "$removed" -gt 0 ]; then check_ok "Teardown complete — $removed component(s) removed"; else check_info "Nothing removed"; fi
echo ""
check_info "Manual cleanup choices:"
check_info "  input group: sudo deluser $USER input"
check_info "  ydotool package: sudo apt remove ydotool"
check_info "  pre-existing Cua WinRects and unrelated GNOME extensions are preserved"
