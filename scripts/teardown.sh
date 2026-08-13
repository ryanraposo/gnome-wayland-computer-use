#!/usr/bin/env bash
# teardown.sh — remove project-owned integration while preserving Cua and Ubuntu foundation.
set -euo pipefail
FORCE=false
[ "${1:-}" = --force ] && FORCE=true
confirm(){ $FORCE && return 0; printf '%s [y/N] ' "$1"; read -r r; [[ "$r" =~ ^[yY] ]]; }
info(){ printf '[INFO] %s\n' "$*"; }
ok(){ printf '[OK] %s\n' "$*"; }
NAME=gnome-wayland-computer-use
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
removed=0

printf '\nGNOME WAYLAND COMPUTER USE // TEARDOWN\n\n'

for unit in gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service; do
    file="$HOME/.config/systemd/user/$unit"
    if [ -f "$file" ]; then
        systemctl --user disable --now "$unit" 2>/dev/null || true
        rm -f "$file"; ((removed++)) || true
    fi
done
systemctl --user daemon-reload 2>/dev/null || true
rm -rf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$NAME" 2>/dev/null || true

# Clean exact project-owned legacy artifacts without touching Cua itself.
legacy="$HOME/.config/systemd/user/gnome-wayland-computer-use.service"
if [ -f "$legacy" ]; then systemctl --user disable --now gnome-wayland-computer-use.service 2>/dev/null || true; rm -f "$legacy"; ((removed++)) || true; fi
legacy="$HOME/.config/systemd/user/ydotoold.service"
if [ -f "$legacy" ] && grep -q 'Description=ydotool uinput daemon' "$legacy"; then systemctl --user disable --now ydotoold.service 2>/dev/null || true; rm -f "$legacy"; ((removed++)) || true; fi
LEGACY_RULE='/etc/udev/rules.d/80-gnome-wayland-computer-use.rules'
LEGACY_RULE_VALUE='KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"'
if [ -f "$LEGACY_RULE" ] && grep -Fxq "$LEGACY_RULE_VALUE" "$LEGACY_RULE" && confirm "Remove the obsolete GWCU uinput rule?"; then
    if command -v pkexec >/dev/null 2>&1; then pkexec rm -f "$LEGACY_RULE"; pkexec udevadm control --reload-rules 2>/dev/null || true
    else sudo rm -f "$LEGACY_RULE"; sudo udevadm control --reload-rules 2>/dev/null || true; fi
    ((removed++)) || true
fi

for dir in "$HOME/.agents/skills/$NAME" "$HERMES_HOME/skills/computer-use" "$HERMES_HOME/skills/$NAME"; do
    [ -d "$dir" ] || continue
    if [ "$dir" = "$HERMES_HOME/skills/computer-use" ] && [ ! -f "$dir/.gnome-wayland-computer-use-managed" ]; then
        info "Preserving user-managed Hermes skill: ${dir/$HOME/\~}"
        continue
    fi
    rm -rf "$dir"; ((removed++)) || true
done

SOUL="$HERMES_HOME/SOUL.md"; START='<!-- gnome-wayland-computer-use:start -->'; END='<!-- gnome-wayland-computer-use:end -->'
if [ -f "$SOUL" ] && grep -Fxq "$START" "$SOUL"; then
    clean=$(mktemp)
    awk -v s="$START" -v e="$END" '$0==s{m=1;next}$0==e{m=0;next}!m{print}' "$SOUL" >"$clean"
    chmod 600 "$clean"; mv "$clean" "$SOUL"; ((removed++)) || true
fi

BACKUPS="$HERMES_HOME/backups/$NAME"; MANIFEST="$BACKUPS/manifest.tsv"
if [ -f "$MANIFEST" ]; then
    remaining=$(mktemp)
    while IFS=$'\t' read -r original backup; do
        [ -n "$original" ] && [ -e "$backup" ] || continue
        if [ -e "$original" ]; then printf '%s\t%s\n' "$original" "$backup" >>"$remaining"
        elif confirm "Restore archived skill to ${original/$HOME/\~}?"; then mkdir -p "$(dirname "$original")"; mv "$backup" "$original"; ((removed++)) || true
        else printf '%s\t%s\n' "$original" "$backup" >>"$remaining"; fi
    done <"$MANIFEST"
    if [ -s "$remaining" ]; then mv "$remaining" "$MANIFEST"; else rm -f "$remaining" "$MANIFEST"; fi
fi

if [ -f "$STATE/ownership.json" ] && command -v python3 >/dev/null 2>&1; then
    previous=$(python3 - "$STATE/ownership.json" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1])); a=d.get('toolkit_accessibility',{})
 print(a.get('previous','unknown') if a.get('changed') else 'unchanged')
except Exception: print('unknown')
PY
)
    if [ "$previous" = true ] || [ "$previous" = false ]; then
        gsettings set org.gnome.desktop.interface toolkit-accessibility "$previous" 2>/dev/null || true
    fi
fi

if [ -e "$STATE/screencast-restore-token" ] && ! $FORCE; then
    if confirm "Remove cached ScreenCast consent token?"; then rm -f "$STATE/screencast-restore-token"; fi
else
    rm -f "$STATE/screencast-restore-token" 2>/dev/null || true
fi
rm -f "$STATE/profile.json" "$STATE/ownership.json" "$STATE/cua-doctor.json" "$STATE/cua-winrects-managed"
rmdir "$STATE" 2>/dev/null || true

printf '\n'; ok "Teardown complete ($removed project component(s) removed)"
info "Preserved Cua Driver, Cua WinRects, Ubuntu PipeWire/portal packages, and unrelated GNOME state."
printf '\n'
