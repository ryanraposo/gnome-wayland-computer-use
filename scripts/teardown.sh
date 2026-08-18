#!/usr/bin/env bash
# teardown.sh — remove GWCU-managed integration and optionally provisioned Cua.
set -euo pipefail

NAME=gnome-wayland-computer-use
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
DEFAULT_CUA_VERSION="0.19.3"
LOGIN_USER="${USER:-$(id -un)}"
FORCE=false
REMOVE_CUA=false
PURGE_CUA=false

usage() {
    cat <<'HELP'
Usage: teardown.sh [--force] [--remove-cua] [--purge-cua]

  --force       perform reversible GWCU cleanup without prompts
  --remove-cua  also remove Cua Driver when GWCU provisioned it
  --purge-cua   remove/purge Cua even if it predated GWCU

WORLDLINE/observer services and transient runtime state are removed.
Repo/workspace .gwcu files are preserved.
HELP
}

while [ $# -gt 0 ]; do
    case "$1" in
        --force) FORCE=true ;;
        --remove-cua) REMOVE_CUA=true ;;
        --purge-cua) REMOVE_CUA=true; PURGE_CUA=true ;;
        --help|-h) usage; exit 0 ;;
        *) printf 'error: unknown option: %s\n' "$1" >&2; exit 2 ;;
    esac
    shift
done

confirm() {
    $FORCE && return 0
    printf '%s [y/N] ' "$1"
    read -r reply
    [[ "$reply" =~ ^[yY] ]]
}
info(){ printf '[INFO] %s\n' "$*"; }
ok(){ printf '[OK] %s\n' "$*"; }
warn(){ printf '[WARN] %s\n' "$*" >&2; }
die(){ printf '[ERROR] %s\n' "$*" >&2; exit 1; }

as_root() {
    if [ "$EUID" -eq 0 ]; then "$@"
    elif command -v pkexec >/dev/null 2>&1; then pkexec "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo "$@"
    else die "pkexec or sudo is required for this cleanup"
    fi
}

remove_managed_path_block() {
    local rc="$1" start='# >>> gnome-wayland-computer-use PATH >>>' end='# <<< gnome-wayland-computer-use PATH <<<' tmp
    [ -f "$rc" ] || return 0
    grep -Fxq "$start" "$rc" || return 0
    tmp=$(mktemp)
    awk -v s="$start" -v e="$end" '$0==s{m=1;next}$0==e{m=0;next}!m{print}' "$rc" >"$tmp"
    chmod --reference="$rc" "$tmp" 2>/dev/null || chmod 600 "$tmp"
    mv "$tmp" "$rc"
}

CUA_PROVISIONED=false
CUA_VERSION="$DEFAULT_CUA_VERSION"
if [ -f "$STATE/ownership.json" ] && command -v python3 >/dev/null 2>&1; then
    mapfile -t values < <(python3 - "$STATE/ownership.json" <<'PY'
import json,sys
try:
    c=json.load(open(sys.argv[1])).get("upstream",{}).get("cua_driver",{})
    print("true" if c.get("provisioned") else "false")
    print(c.get("version") or "0.19.3")
except Exception:
    print("false"); print("0.19.3")
PY
)
    CUA_PROVISIONED="${values[0]:-false}"
    CUA_VERSION="${values[1]:-$DEFAULT_CUA_VERSION}"
fi

uninstall_cua() {
    local tmp url args=()
    if ! $PURGE_CUA && [ "$CUA_PROVISIONED" != true ]; then
        info "Preserving Cua Driver because it existed before GWCU."
        return
    fi
    command -v curl >/dev/null 2>&1 || die "curl is required for Cua uninstall"
    case "$CUA_VERSION" in ''|*[!0-9.]* ) CUA_VERSION="$DEFAULT_CUA_VERSION" ;; esac
    url="https://raw.githubusercontent.com/trycua/cua/cua-driver-rs-v${CUA_VERSION}/libs/cua-driver/scripts/uninstall.sh"
    tmp=$(mktemp)
    curl -fsSL --retry 3 --retry-delay 1 -o "$tmp" "$url" ||
        die "Could not fetch Cua $CUA_VERSION uninstaller"
    $PURGE_CUA && args+=(--purge)
    /bin/bash "$tmp" "${args[@]}" || die "Cua Driver uninstall failed"
    rm -f "$tmp"
}

printf '\nCOMPUTER USE // WORLDLINE // UNINSTALL\n\n'
removed=0

# WORLDLINE and observer are GWCU owned transient user services.
for unit in \
    gnome-wayland-computer-use-worldline.socket \
    gnome-wayland-computer-use-worldline.service \
    gnome-wayland-computer-use-observer.socket \
    gnome-wayland-computer-use-observer.service
do
    file="$HOME/.config/systemd/user/$unit"
    systemctl --user disable --now "$unit" 2>/dev/null || true
    systemctl --user reset-failed "$unit" 2>/dev/null || true
    if [ -f "$file" ]; then rm -f "$file"; ((removed++)) || true; fi
done
systemctl --user daemon-reload 2>/dev/null || true
rm -rf "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$NAME" 2>/dev/null || true

# Retire only exact historical GWCU artifacts.
legacy="$HOME/.config/systemd/user/gnome-wayland-computer-use.service"
if [ -f "$legacy" ]; then
    systemctl --user disable --now gnome-wayland-computer-use.service 2>/dev/null || true
    rm -f "$legacy"; ((removed++)) || true
fi
legacy="$HOME/.config/systemd/user/ydotoold.service"
if [ -f "$legacy" ] && grep -q 'Description=ydotool uinput daemon' "$legacy"; then
    systemctl --user disable --now ydotoold.service 2>/dev/null || true
    rm -f "$legacy"; ((removed++)) || true
fi
LEGACY_RULE='/etc/udev/rules.d/80-gnome-wayland-computer-use.rules'
LEGACY_RULE_VALUE='KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"'
if [ -f "$LEGACY_RULE" ] && grep -Fxq "$LEGACY_RULE_VALUE" "$LEGACY_RULE" &&
   confirm "Remove the obsolete GWCU uinput rule?"; then
    as_root rm -f "$LEGACY_RULE"
    as_root udevadm control --reload-rules 2>/dev/null || true
    ((removed++)) || true
fi

for rc in "$HOME/.profile" "$HOME/.bashrc" "$HOME/.zshrc"; do
    remove_managed_path_block "$rc"
done

if [ -f "$STATE/video-group-added" ]; then
    if getent group video >/dev/null 2>&1 &&
       id -nG "$LOGIN_USER" 2>/dev/null | tr ' ' '\n' | grep -Fxq video &&
       confirm "Remove $LOGIN_USER from the video group that GWCU added?"; then
        as_root gpasswd -d "$LOGIN_USER" video >/dev/null ||
            warn "Could not remove $LOGIN_USER from video group"
    fi
    rm -f "$STATE/video-group-added"
fi

# Remove every GWCU-owned Hermes plugin copy. A stale duplicate (same
# plugin.yaml name, different directory) would otherwise keep /computer-use
# registered after teardown.
plugin_name_of(){ awk -F': *' '/^name:[[:space:]]*/{gsub(/^[[:space:]]+|[[:space:]]+$|["'\'']/,"",$2); print $2; exit}' "$1"; }
for yaml in "$HERMES_HOME/plugins"/*/plugin.yaml; do
    [ -f "$yaml" ] || continue
    name=$(plugin_name_of "$yaml"); [ "$name" = "$NAME" ] || continue
    dir=$(dirname "$yaml")
    if [ -f "$dir/.gnome-wayland-computer-use-managed" ]; then
        command -v hermes >/dev/null 2>&1 && hermes plugins disable "$NAME" >/dev/null 2>&1 || true
        rm -rf "$dir"; ((removed++)) || true
    else
        info "Preserving user-managed Hermes plugin: ${dir/$HOME/\~}"
    fi
done

for dir in \
    "$HOME/.agents/skills/$NAME" \
    "$HERMES_HOME/skills/computer-use" \
    "$HERMES_HOME/skills/$NAME"
do
    [ -d "$dir" ] || continue
    if [ ! -f "$dir/.gnome-wayland-computer-use-managed" ]; then
        info "Preserving user-managed skill: ${dir/$HOME/\~}"
        continue
    fi
    rm -rf "$dir"; ((removed++)) || true
done

SOUL="$HERMES_HOME/SOUL.md"
START='<!-- gnome-wayland-computer-use:start -->'
END='<!-- gnome-wayland-computer-use:end -->'
if [ -f "$SOUL" ] && grep -Fxq "$START" "$SOUL"; then
    clean=$(mktemp)
    awk -v s="$START" -v e="$END" '$0==s{m=1;next}$0==e{m=0;next}!m{print}' "$SOUL" >"$clean"
    chmod 600 "$clean"; mv "$clean" "$SOUL"; ((removed++)) || true
fi

BACKUPT="$HERMES_HOME/backups/$NAME"
MANIFEST="$BACKUPT/manifest.tsv"
if [ -f "$MANIFEST" ]; then
    remaining=$(mktemp)
    while IFS=$'\t' read -r original backup; do
        [ -n "$original" ] && [ -e "$backup" ] || continue
        if [ -e "$original" ]; then
            printf '%s\t%s\n' "$original" "$backup" >>"$remaining"
        elif confirm "Restore archived component to ${original/$HOME/\~}?"; then
            mkdir -p "$(dirname "$original")"; mv "$backup" "$original"
            ((removed++)) || true
        else
            printf '%s\t%s\n' "$original" "$backup" >>"$remaining"
        fi
    done <"$MANIFEST"
    if [ -s "$remaining" ]; then mv "$remaining" "$MANIFEST"
    else rm -f "$remaining" "$MANIFEST"
    fi
fi

if [ -f "$STATE/ownership.json" ] && command -v python3 >/dev/null 2>&1; then
    previous=$(python3 - "$STATE/ownership.json" <<'PY'
import json,sys
try:
    a=json.load(open(sys.argv[1])).get("toolkit_accessibility",{})
    print(a.get("previous","unknown") if a.get("changed") else "unchanged")
except Exception: print("unknown")
PY
)
    if [ "$previous" = true ] || [ "$previous" = false ]; then
        gsettings set org.gnome.desktop.interface toolkit-accessibility "$previous" 2>/dev/null || true
    fi
fi

$REMOVE_CUA && uninstall_cua

rm -f \
    "$STATE/screencast-restore-token" \
    "$STATE/profile.json" "$STATE/ownership.json" \
    "$STATE/cua-doctor.json" "$STATE/cua-doctor.stderr" "$STATE/cua-health.json" \
    "$STATE/cua-winrects-managed" "$STATE/video-group-added" \
    "$STATE/managed-truths" "$STATE/managed-agents" "$STATE/portal-control.json"
rmdir "$STATE" 2>/dev/null || true

printf '\n'; ok "Teardown complete ($removed project component(s) removed)"
info "WORLDLINE and observer runtime state were removed."
info "Ubuntu PipeWire/portal packages and GNOME portal permission state were preserved."
info "Repo/workspace .gwcu files and their .gitignore protection were preserved as local workspace content."
if ! $REMOVE_CUA; then info "Cua Driver and Cua WinRects were preserved."; fi
printf '\n'
