#!/usr/bin/env bash
# install.sh — install the Ubuntu GNOME integration around Cua Driver.
set -euo pipefail

NAME="gnome-wayland-computer-use"
VERSION="2.3.0"
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"

# Deliberately pinned. Do not replace this with "latest".
# Cua Driver 0.19.3's standard Linux release artifact provides the portal-input
# path used by GNOME RemoteDesktop -> EIS/libei control.
CUA_DRIVER_RS_VERSION="${GWCU_CUA_DRIVER_RS_VERSION:-0.19.3}"

SELF=""
[ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ] && SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

as_root() {
    if command -v pkexec >/dev/null 2>&1; then pkexec "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo "$@"
    else die "pkexec or sudo is required for host repair"
    fi
}

get_file() {
    local rel="$1" dst="$2"
    mkdir -p "$(dirname "$dst")"
    if [ -n "$SELF" ] && [ -f "$SELF/$rel" ]; then
        cp "$SELF/$rel" "$dst"
    else
        command -v curl >/dev/null 2>&1 || die "curl is required for remote installation"
        curl -fsSL --retry 3 --retry-delay 1 -o "$dst" "$BASE_URL/$rel" || die "Could not download $rel"
    fi
}

session_type() {
    local value="${XDG_SESSION_TYPE:-}"
    [ -n "$value" ] || value=$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Type --value 2>/dev/null || true)
    printf '%s\n' "${value:-unknown}"
}

desktop_name() {
    local value="${XDG_CURRENT_DESKTOP:-}"
    [ -n "$value" ] || value=$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Desktop --value 2>/dev/null || true)
    printf '%s\n' "${value:-unknown}"
}

portal_has() {
    local iface="$1"
    command -v gdbus >/dev/null 2>&1 || return 1
    gdbus introspect --session --dest org.freedesktop.portal.Desktop \
        --object-path /org/freedesktop/portal/desktop 2>/dev/null |
        grep -q "interface org.freedesktop.portal.${iface}"
}

pipewire_ready() {
    command -v pw-cli >/dev/null 2>&1 && pw-cli info 0 >/dev/null 2>&1
}

gi_ready() {
    [ -x /usr/bin/python3 ] || return 1
    /usr/bin/python3 - <<'PY' >/dev/null 2>&1
import gi
for name, version in (("Gio","2.0"),("Gst","1.0"),("GstVideo","1.0"),("GdkPixbuf","2.0")):
    gi.require_version(name, version)
from gi.repository import Gio, Gst, GstVideo, GdkPixbuf
PY
}

resolve_cua() {
    local p
    p=$(command -v cua-driver 2>/dev/null || true)
    if [ -n "$p" ]; then printf '%s\n' "$p"; return 0; fi
    [ -x "$HOME/.local/bin/cua-driver" ] && { printf '%s\n' "$HOME/.local/bin/cua-driver"; return 0; }
    return 1
}

ensure_managed_path() {
    export PATH="$HOME/.local/bin:$PATH"
    case ":${PATH_BEFORE:-}:" in
        *":$HOME/.local/bin:"*) return 0 ;;
    esac

    local files=("$HOME/.profile")
    case "${SHELL##*/}" in
        bash) files+=("$HOME/.bashrc") ;;
        zsh) files+=("$HOME/.zshrc") ;;
    esac

    local f
    for f in "${files[@]}"; do
        mkdir -p "$(dirname "$f")"
        touch "$f"
        grep -Fq '# >>> gnome-wayland-computer-use PATH >>>' "$f" && continue
        cat >>"$f" <<'PATHBLOCK'

# >>> gnome-wayland-computer-use PATH >>>
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH" ;;
esac
# <<< gnome-wayland-computer-use PATH <<<
PATHBLOCK
    done
}

refresh_cua() {
    command -v curl >/dev/null 2>&1 || die "curl is required to install Cua Driver"
    info "Installing pinned Cua Driver $CUA_DRIVER_RS_VERSION"
    CUA_DRIVER_RS_VERSION="$CUA_DRIVER_RS_VERSION" \
    CUA_DRIVER_RS_NO_MODIFY_PATH=1 \
        /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)" ||
        die "Pinned Cua Driver installer failed"
    export PATH="$HOME/.local/bin:$PATH"
    CUA=$(resolve_cua || true)
    [ -n "$CUA" ] || die "cua-driver is unavailable after the official installer"
    local reported
    reported=$("$CUA" --version 2>/dev/null || true)
    printf '%s' "$reported" | grep -Fq "$CUA_DRIVER_RS_VERSION" ||
        die "Expected Cua Driver $CUA_DRIVER_RS_VERSION after install; got: ${reported:-unknown}"
}

doctor_hints() {
    local file="$1"
    [ -s "$file" ] || return 0
    /usr/bin/python3 - "$file" <<'PY' 2>/dev/null || true
import json, sys
try:
    data=json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    raise SystemExit(0)
keys={"hint","hints","message","detail","details","recovery","recommendation","recommendations","next","action","fix"}
out=[]
def walk(x, key=""):
    if isinstance(x, dict):
        for k,v in x.items(): walk(v, str(k).lower())
    elif isinstance(x, list):
        for v in x: walk(v, key)
    elif isinstance(x, str) and (key in keys or any(t in x.lower() for t in ("permission","portal","remote desktop","wayland","drm","pipewire","winrects"))):
        s=" ".join(x.split())
        if s and s not in out: out.append(s)
walk(data)
for s in out[:12]: print(f"  - {s}")
PY
}

doctor_mentions_drm() {
    local out="$1" err="$2"
    { cat "$out" 2>/dev/null || true; cat "$err" 2>/dev/null || true; } |
        grep -Eiq '(/dev/dri|DRM|render node|video group|permission[^[:cntrl:]]*(card|render|gpu))'
}

maybe_add_video_group() {
    local out="$1" err="$2"
    doctor_mentions_drm "$out" "$err" || return 1
    id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -qx video && return 1

    local add=false response
    if $UNATTENDED; then
        add=true
    else
        printf 'Cua reported a DRM access problem. Add %s to the video group? [Y/n] ' "$LOGIN_USER"
        read -r response || true
        [[ ! "$response" =~ ^[nN] ]] && add=true
    fi
    $add || return 1

    as_root adduser "$LOGIN_USER" video || die "Could not add $LOGIN_USER to the video group"
    : >"$STATE/video-group-added"
    warn "Added $LOGIN_USER to video because Cua explicitly reported DRM access trouble."
    warn "Group membership takes effect after signing out of GNOME and back in."
    return 0
}

managed_truths_setup() {
    local pref="$STATE/managed-truths" legacy="$STATE/managed-agents" response value=on

    if [ ! -s "$pref" ] && [ -s "$legacy" ]; then
        IFS= read -r value <"$legacy" || value=on
        case "${value,,}" in off|no|false|0) value=off ;; *) value=on ;; esac
        printf '%s\n' "$value" >"$pref.tmp"
        chmod 600 "$pref.tmp"
        mv -f "$pref.tmp" "$pref"
        rm -f "$legacy"
        ok "Migrated managed-truth preference from the pre-.gwcu installer"
    fi

    if [ -s "$pref" ]; then
        IFS= read -r value <"$pref" || value=on
        case "${value,,}" in off|no|false|0) value=off ;; *) value=on ;; esac
        ok "Managed .gwcu truths already configured: $value"
        return 0
    fi

    if ! $EXPLICIT_UNATTENDED && [ -r /dev/tty ]; then
        printf 'Enable managed .gwcu local truths? Git scopes will add /.gwcu to .gitignore before storing machine/workspace facts [Y/n]: ' >/dev/tty
        read -r response </dev/tty || response=""
        [[ "$response" =~ ^[nN] ]] && value=off
    fi

    printf '%s\n' "$value" >"$pref.tmp"
    chmod 600 "$pref.tmp"
    mv -f "$pref.tmp" "$pref"
    if [ "$value" = on ]; then
        ok "Managed .gwcu truths enabled (repo/workspace-local; Git scopes are ignored before write)"
    else
        ok "Managed .gwcu truths disabled"
    fi
}

countdown_portal() {
    local n
    info "GNOME calls its compositor-approved local pointer/keyboard permission 'Remote Desktop'."
    info "Cua uses that portal only to obtain an EIS/libei input session; GWCU installs no RDP/VNC server or raw-input daemon."
    info "The one-time handshake sends no click or key. It only moves the pointer once."
    printf '\n'
    for n in 3 2 1; do
        printf '\r\033[34m[INFO]\033[0m GNOME permission prompt may appear in %s... ' "$n"
        sleep 1
    done
    printf '\r\033[34m[INFO]\033[0m Approve the GNOME Remote Desktop / remote-control prompt if it appears.          \n'
}

COMPAT=false
UNATTENDED=false
EXPLICIT_UNATTENDED=false
HERMES_MODE=auto
for arg in "$@"; do
    case "$arg" in
        --compat) COMPAT=true ;;
        --unattended) UNATTENDED=true; EXPLICIT_UNATTENDED=true ;;
        --hermes) HERMES_MODE=require ;;
        --agent-only) HERMES_MODE=skip ;;
        --help|-h)
            cat <<'HELP'
Usage: install.sh [--compat] [--unattended] [--hermes|--agent-only]
  --hermes      require Hermes and install its skill + /computer-use command plugin
  --agent-only  skip Hermes-specific files; Cua Driver is still the control authority
  --compat      stage files without requiring a live Ubuntu GNOME Wayland session
  --unattended  accept installer defaults; privilege/portal UI can still appear

Environment:
  GWCU_CUA_DRIVER_RS_VERSION=<version>  deliberate release qualification override
  GWCU_TRUTHS=off                       runtime override for managed .gwcu truth use
  GWCU_SCOPE_ROOT=<path>                explicit non-Git/repo truth scope override
HELP
            exit 0
            ;;
        *) die "Unknown option: $arg" ;;
    esac
done

[ "$EUID" -ne 0 ] || die "Run as the logged-in desktop user, not with sudo"
LOGIN_USER="${USER:-$(id -un)}"
if [ ! -t 0 ] && ! $UNATTENDED; then UNATTENDED=true; fi

HERMES=false
case "$HERMES_MODE" in
    auto) command -v hermes >/dev/null 2>&1 && HERMES=true || true ;;
    require) command -v hermes >/dev/null 2>&1 || die "--hermes requested but hermes is not on PATH"; HERMES=true ;;
    skip) ;;
esac

printf '\nCOMPUTER USE // UBUNTU 26\n\n'

info "[1/8] Detecting Ubuntu + desktop session"
[ -r /etc/os-release ] || die "/etc/os-release is required for distro selection"
# shellcheck disable=SC1091
. /etc/os-release
DISTRO_ID="${ID:-unknown}"
DISTRO_VERSION="${VERSION_ID:-unknown}"
DISTRO_CODENAME="${VERSION_CODENAME:-unknown}"
if [ "$DISTRO_ID" != ubuntu ] || [ "$DISTRO_VERSION" != 26.04 ]; then
    if ! $COMPAT; then
        die "This installer is qualified for Ubuntu 26.04; found ${DISTRO_ID} ${DISTRO_VERSION}. Use --compat only to stage files intentionally."
    fi
    warn "Compatibility install on ${DISTRO_ID} ${DISTRO_VERSION} (${DISTRO_CODENAME}); skipping Ubuntu package mutation."
else
    ok "Ubuntu 26.04 (${DISTRO_CODENAME})"
fi

SESSION=$(session_type)
DESKTOP=$(desktop_name)
if [ "$SESSION" != wayland ] || [[ "$DESKTOP" != *GNOME* ]]; then
    if ! $COMPAT; then die "Expected an active GNOME Wayland session; found session=$SESSION desktop=$DESKTOP"; fi
    warn "Compatibility install: session=$SESSION desktop=$DESKTOP"
else
    ok "GNOME Wayland session"
fi

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
mkdir -p "$STATE"; chmod 700 "$STATE" 2>/dev/null || true

info "[2/8] Preparing Ubuntu portal/accessibility foundation"
if [ "$DISTRO_ID" = ubuntu ] && [ "$DISTRO_VERSION" = 26.04 ]; then
    APT_PACKAGES=(
        ca-certificates curl
        libglib2.0-bin
        pipewire pipewire-bin wireplumber
        xdg-desktop-portal xdg-desktop-portal-gnome
        python3 python3-dbus python3-gi python3-gst-1.0
        gstreamer1.0-tools gstreamer1.0-pipewire
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good
        gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0
        at-spi2-core
        libei1 libxkbcommon0
    )
    missing=()
    for pkg in "${APT_PACKAGES[@]}"; do
        dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'ok installed' || missing+=("$pkg")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        info "Elevating once to install: ${missing[*]}"
        if ! as_root apt-get install -y --no-install-recommends "${missing[@]}"; then
            info "Refreshing apt metadata and retrying once"
            as_root apt-get update
            as_root apt-get install -y --no-install-recommends "${missing[@]}" || die "Ubuntu dependency repair failed"
        fi
    fi

    PW_VERSION=$(dpkg-query -W -f='${Version}' pipewire 2>/dev/null | sed 's/^[0-9][0-9]*://;s/-.*//' || true)
    [ -n "$PW_VERSION" ] || die "Could not determine the installed PipeWire version"
    dpkg --compare-versions "$PW_VERSION" ge 0.3.40 || die "PipeWire >= 0.3.40 is required; Ubuntu package reports $PW_VERSION"
    ok "PipeWire $PW_VERSION satisfies the >= 0.3.40 floor"
fi

systemctl --user start pipewire.socket pipewire.service wireplumber.service 2>/dev/null || true
systemctl --user start xdg-desktop-portal.service xdg-desktop-portal-gnome.service 2>/dev/null || true
systemctl --user reset-failed gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service 2>/dev/null || true

if ! $COMPAT; then
    pipewire_ready || die "PipeWire is unavailable after package repair"
    gi_ready || die "Python GI/GStreamer observation bindings are unavailable after package repair"
    portal_has ScreenCast || die "GNOME ScreenCast portal is unavailable"
    portal_has Screenshot || die "GNOME Screenshot portal is unavailable"
    portal_has RemoteDesktop || die "GNOME RemoteDesktop portal is unavailable; Cua portal input cannot be established"
fi
ok "RemoteDesktop, ScreenCast, Screenshot, PipeWire, D-Bus/GI and AT-SPI foundation prepared"

rm -f "$STATE/cua-winrects-managed"
PREV_ACCESSIBILITY=unknown
ACCESSIBILITY_CHANGED=false
if command -v gsettings >/dev/null 2>&1; then
    PREV_ACCESSIBILITY=$(gsettings get org.gnome.desktop.interface toolkit-accessibility 2>/dev/null || printf unknown)
    if [ "$PREV_ACCESSIBILITY" != true ]; then
        gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null || true
        ACCESSIBILITY_CHANGED=true
    fi
fi
systemctl --user start at-spi-bus-launcher.service 2>/dev/null || true

info "[3/8] Installing qualified Cua Driver"
PATH_BEFORE="$PATH"
PRE_CUA=$(resolve_cua || true)
CUA_INSTALLED_BY_GWCU=false
if [ -f "$STATE/ownership.json" ]; then
    PRIOR_CUA_OWNED=$(/usr/bin/python3 - "$STATE/ownership.json" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1],encoding="utf-8"))
    print("true" if d.get("upstream",{}).get("cua_driver",{}).get("provisioned") else "false")
except Exception:
    print("false")
PY
)
    [ "$PRIOR_CUA_OWNED" = true ] && CUA_INSTALLED_BY_GWCU=true
fi
[ -n "$PRE_CUA" ] || CUA_INSTALLED_BY_GWCU=true
ensure_managed_path
if [ -n "$PRE_CUA" ] && "$PRE_CUA" --version 2>/dev/null | grep -Fq "$CUA_DRIVER_RS_VERSION"; then
    CUA="$PRE_CUA"
    ok "Qualified Cua Driver $CUA_DRIVER_RS_VERSION already installed"
else
    refresh_cua
fi
"$CUA" describe health_report >/dev/null 2>&1 || die "Pinned Cua Driver does not expose the stable health_report surface"
ok "Cua Driver $CUA_DRIVER_RS_VERSION: $CUA"

CUA_HOME="${CUA_DRIVER_HOME:-$HOME/.cua-driver}"
HELPER="$CUA_HOME/packages/current/wayland-helper"
CUA_HELPER_INSTALLER="$HELPER/install.sh"
WINRECTS_UUID='winrects@cua'
WINRECTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$WINRECTS_UUID"
[ -x "$CUA_HELPER_INSTALLER" ] || die "Pinned Cua package is missing its GNOME helper: $CUA_HELPER_INSTALLER"

helper_matches=false
if [ -f "$HELPER/$WINRECTS_UUID/extension.js" ] && [ -f "$WINRECTS_DIR/extension.js" ] && \
   [ -f "$HELPER/$WINRECTS_UUID/metadata.json" ] && [ -f "$WINRECTS_DIR/metadata.json" ] && \
   cmp -s "$HELPER/$WINRECTS_UUID/extension.js" "$WINRECTS_DIR/extension.js" && \
   cmp -s "$HELPER/$WINRECTS_UUID/metadata.json" "$WINRECTS_DIR/metadata.json"; then
    helper_matches=true
fi
helper_was_active=false
if command -v gnome-extensions >/dev/null 2>&1 && gnome-extensions info "$WINRECTS_UUID" 2>/dev/null | grep -q 'State:[[:space:]]*ACTIVE'; then
    helper_was_active=true
fi
helper_changed=false
$helper_matches || helper_changed=true
if ! $helper_matches || ! $helper_was_active; then
    "$CUA_HELPER_INSTALLER" || die "Cua WinRects helper installation failed"
fi
[ -d "$WINRECTS_DIR" ] || die "Cua WinRects was not installed"

helper_active=false
if command -v gnome-extensions >/dev/null 2>&1 && gnome-extensions info "$WINRECTS_UUID" 2>/dev/null | grep -q 'State:[[:space:]]*ACTIVE'; then
    helper_active=true
fi
RELOAD_REQUIRED=false
if ! $helper_changed && $helper_active; then
    ok "Cua GNOME helper current and active"
else
    RELOAD_REQUIRED=true
    warn "Cua GNOME helper installed/updated; the current Shell may need one reload/sign-out cycle"
fi

info "[4/8] Installing the agent operating layer"
PRIMARY="$HOME/.agents/skills/$NAME"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_SKILL="$HERMES_HOME/skills/computer-use"
HERMES_PLUGIN="$HERMES_HOME/plugins/$NAME"
BACKUPS="$HERMES_HOME/backups/$NAME"
MANAGED='.gnome-wayland-computer-use-managed'

archive_dir() {
    local src="$1" label="$2" stamp dst
    [ -d "$src" ] || return 0
    stamp=$(date +%Y%m%d-%H%M%S)-$$
    dst="$BACKUPS/$stamp/$label"
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
    mkdir -p "$BACKUPS"
    printf '%s\t%s\n' "$src" "$dst" >> "$BACKUPS/manifest.tsv"
}

install_bundle() {
    local dst="$1" skill_src="$2" rel
    if [ -d "$dst" ] && [ ! -f "$dst/$MANAGED" ]; then archive_dir "$dst" "$(basename "$dst")"; fi
    rm -rf "$dst"
    mkdir -p "$dst/scripts" "$dst/references" "$dst/systemd/user"
    get_file "$skill_src" "$dst/SKILL.md"
    get_file uninstall.sh "$dst/uninstall.sh"
    for rel in VERSION references/skill-ux-contract.md \
        scripts/app-identity.sh scripts/capture.sh scripts/check-update.sh scripts/computer-use.sh \
        scripts/cua-health.py scripts/diagnose.sh scripts/observe.sh scripts/observer.py \
        scripts/portal-control.py scripts/profile.sh scripts/teardown.sh scripts/truths.py \
        systemd/user/gnome-wayland-computer-use-observer.socket \
        systemd/user/gnome-wayland-computer-use-observer.service; do
        get_file "$rel" "$dst/$rel"
    done
    [ "$(tr -d '[:space:]' < "$dst/VERSION")" = "$VERSION" ] || die "Installer payload version mismatch"
    grep -qx "version: $VERSION" "$dst/SKILL.md" || die "Installer skill payload version mismatch"
    chmod +x "$dst/uninstall.sh" "$dst/scripts/"*.sh "$dst/scripts/"*.py
    : > "$dst/$MANAGED"
}

install_bundle "$PRIMARY" runtimes/openai/SKILL.md
mkdir -p "$PRIMARY/agents"
get_file agents/openai.yaml "$PRIMARY/agents/openai.yaml"
managed_truths_setup

if $HERMES; then
    install_bundle "$HERMES_SKILL" SKILL.md
    if [ -d "$HERMES_PLUGIN" ] && [ ! -f "$HERMES_PLUGIN/$MANAGED" ]; then
        archive_dir "$HERMES_PLUGIN" "plugin-$NAME"
    fi
    rm -rf "$HERMES_PLUGIN"
    mkdir -p "$HERMES_PLUGIN"
    get_file runtimes/hermes/plugin.yaml "$HERMES_PLUGIN/plugin.yaml"
    get_file runtimes/hermes/__init__.py "$HERMES_PLUGIN/__init__.py"
    : >"$HERMES_PLUGIN/$MANAGED"
    if ! hermes plugins enable "$NAME" >/dev/null 2>&1; then
        die "Hermes plugin command API is unavailable. Update Hermes, then rerun the installer."
    fi
    ok "Hermes /computer-use command registered and enabled"

    if [ -d "$HERMES_HOME/skills" ]; then
        while IFS= read -r -d '' f; do
            d=$(dirname "$f")
            [ "$d" = "$HERMES_SKILL" ] && continue
            if grep -qiE '(^|[^[:alnum:]_-])(grim|slurp|gnome-screenshot)([^[:alnum:]_-]|$)' "$f"; then
                archive_dir "$d" "$(basename "$d")"
            fi
        done < <(find "$HERMES_HOME/skills" -type f -name SKILL.md -print0 2>/dev/null)
    fi
fi
ok "Agent operating layer installed"

info "[5/8] Completing one-time GNOME control consent"
if ! $COMPAT; then
    set +e
    PORTAL_STATUS=$("$PRIMARY/scripts/portal-control.py" --status --driver "$CUA" 2>/dev/null)
    set -e
    TOKEN_PRESENT=$(/usr/bin/python3 - "$PORTAL_STATUS" <<'PY'
import json,sys
try:d=json.loads(sys.argv[1]); print('true' if d.get('portal',{}).get('restore_token',{}).get('present') else 'false')
except Exception: print('false')
PY
)
    if [ "$TOKEN_PRESENT" = true ]; then
        ok "GNOME RemoteDesktop restore token already present; no repeat prompt needed"
    else
        countdown_portal
        AUTH_RC=0
        "$PRIMARY/scripts/portal-control.py" --authorize --driver "$CUA" --timeout 90 >"$STATE/portal-control.json.tmp" || AUTH_RC=$?
        if [ "$AUTH_RC" -ne 0 ]; then
            [ ! -s "$STATE/portal-control.json.tmp" ] || cat "$STATE/portal-control.json.tmp" >&2
            rm -f "$STATE/portal-control.json.tmp"
            die "RemoteDesktop authorization was not established. Approve the GNOME prompt and rerun install.sh."
        fi
        chmod 600 "$STATE/portal-control.json.tmp"
        mv -f "$STATE/portal-control.json.tmp" "$STATE/portal-control.json"
        ok "GNOME RemoteDesktop/EIS control permission established"
    fi
    info "Verify anytime with /computer-use consent or $PRIMARY/scripts/portal-control.py --status"
else
    warn "Compatibility mode: RemoteDesktop consent will be established in the live Ubuntu GNOME session"
fi

info "[6/8] Retiring stale project control artifacts"
LEGACY_SERVICE="$HOME/.config/systemd/user/gnome-wayland-computer-use.service"
if [ -f "$LEGACY_SERVICE" ]; then
    systemctl --user disable --now gnome-wayland-computer-use.service 2>/dev/null || true
    rm -f "$LEGACY_SERVICE"
fi
LEGACY_YDO="$HOME/.config/systemd/user/ydotoold.service"
if [ -f "$LEGACY_YDO" ] && grep -q 'Description=ydotool uinput daemon' "$LEGACY_YDO"; then
    systemctl --user disable --now ydotoold.service 2>/dev/null || true
    rm -f "$LEGACY_YDO"
fi
LEGACY_RULE='/etc/udev/rules.d/80-gnome-wayland-computer-use.rules'
LEGACY_RULE_VALUE='KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"'
if [ -f "$LEGACY_RULE" ] && grep -Fxq "$LEGACY_RULE_VALUE" "$LEGACY_RULE"; then
    as_root rm -f "$LEGACY_RULE"
    as_root udevadm control --reload-rules 2>/dev/null || true
fi
LEGACY_EXT="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use"
if [ -d "$LEGACY_EXT" ]; then
    command -v gnome-extensions >/dev/null 2>&1 && gnome-extensions disable desktop-capture@gnome-wayland-computer-use 2>/dev/null || true
    rm -rf "$LEGACY_EXT"
fi
systemctl --user daemon-reload 2>/dev/null || true
systemctl --user reset-failed gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service gnome-wayland-computer-use.service ydotoold.service 2>/dev/null || true
ok "No custom udev/input daemon remains"

info "[7/8] Enabling lazy whole-screen observation"
UNIT_DIR="$HOME/.config/systemd/user"
mkdir -p "$UNIT_DIR"
cp "$PRIMARY/systemd/user/gnome-wayland-computer-use-observer.socket" "$UNIT_DIR/"
cp "$PRIMARY/systemd/user/gnome-wayland-computer-use-observer.service" "$UNIT_DIR/"
systemctl --user daemon-reload || $COMPAT || die "Could not reload user systemd"
if ! $COMPAT; then
    systemctl --user enable --now gnome-wayland-computer-use-observer.socket || die "Could not enable observer socket"
    systemctl --user is-active --quiet gnome-wayland-computer-use-observer.socket || die "Observer socket is not active"
fi
/usr/bin/python3 "$PRIMARY/scripts/observer.py" self-test >/dev/null || die "Observer self-test failed"
ok "Private socket-activated ScreenCast observer ready"

if $HERMES; then
    SOUL="$HERMES_HOME/SOUL.md"
    START='<!-- gnome-wayland-computer-use:start -->'; END='<!-- gnome-wayland-computer-use:end -->'
    mkdir -p "$HERMES_HOME"
    clean=$(mktemp); next=$(mktemp)
    if [ -f "$SOUL" ]; then
        awk -v s="$START" -v e="$END" '$0==s{m=1;next}$0==e{m=0;next}!m{print}' "$SOUL" >"$clean"
    else
        : >"$clean"
    fi
    {
        printf '%s\n' "$START"
        cat <<'SOUL'
## Ubuntu GNOME computer use

Use Hermes `computer_use` normally; Cua Driver is the control authority for semantics,
pixels, geometry, activation, input delivery, verification, and refusals. The first
install establishes GNOME's Remote Desktop portal permission for Cua's local EIS/libei
pointer/keyboard path; a separate first whole-screen observation may show ScreenCast
consent.

Use `/computer-use status` for a compact runtime view, `/computer-use consent` to verify
the local portal contract, `/computer-use managed [on|off|status]` for repo/workspace
`.gwcu` persistence, `/computer-use truths` to show the current truth scope, and
`/computer-use doctor` for deterministic diagnosis. Persistent machine/workspace truth
belongs in `.gwcu`, never AGENTS.md. Live Cua state wins on contradiction.

For explicit whole-screen observation, use the installed observer. Do not invent a
raw-input fallback when Cua refuses a delivery shape.
SOUL
        printf '%s\n' "$END"
        [ ! -s "$clean" ] || { printf '\n'; cat "$clean"; }
    } >"$next"
    chmod 600 "$next"; mv "$next" "$SOUL"; rm -f "$clean"
fi

/usr/bin/python3 - "$STATE/ownership.json" "$PREV_ACCESSIBILITY" "$ACCESSIBILITY_CHANGED" \
    "$CUA_INSTALLED_BY_GWCU" "$CUA_DRIVER_RS_VERSION" "$HERMES" <<'PY'
import json, os, pathlib, sys
p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True,exist_ok=True)
d={
 "schema":"gwcu.ownership.v2",
 "toolkit_accessibility":{"previous":sys.argv[2],"changed":sys.argv[3]=="true"},
 "upstream":{"cua_driver":{"provisioned":sys.argv[4]=="true","owned":sys.argv[4]=="true","version":sys.argv[5]},"winrects":{"owned":False}},
 "user_units":{"observer_socket":True,"observer_service":True},
 "hermes_plugin":{"managed":sys.argv[6]=="true","name":"gnome-wayland-computer-use"},
 "path_marker":"gnome-wayland-computer-use PATH",
 "groups":{"video_added":(p.parent/"video-group-added").exists()},
 "distro_foundation_owned":False,
}
t=p.with_suffix(".tmp"); t.write_text(json.dumps(d,separators=(",",":"))+"\n"); os.chmod(t,0o600); os.replace(t,p)
PY

info "[8/8] Proving installed-state health"
if ! $COMPAT; then
    DOCTOR_OUT="$STATE/cua-doctor.json"
    DOCTOR_ERR="$STATE/cua-doctor.stderr"
    DOCTOR_RC=0
    "$CUA" doctor --json >"$DOCTOR_OUT.tmp" 2>"$DOCTOR_ERR.tmp" || DOCTOR_RC=$?
    if [ -s "$DOCTOR_OUT.tmp" ]; then chmod 600 "$DOCTOR_OUT.tmp"; mv "$DOCTOR_OUT.tmp" "$DOCTOR_OUT"; else rm -f "$DOCTOR_OUT.tmp"; : >"$DOCTOR_OUT"; fi
    if [ -s "$DOCTOR_ERR.tmp" ]; then chmod 600 "$DOCTOR_ERR.tmp"; mv "$DOCTOR_ERR.tmp" "$DOCTOR_ERR"; else rm -f "$DOCTOR_ERR.tmp"; : >"$DOCTOR_ERR"; fi
    if [ "$DOCTOR_RC" -ne 0 ]; then
        printf '\nCua doctor hints:\n' >&2
        HINT_TEXT=$(doctor_hints "$DOCTOR_OUT")
        if [ -n "$HINT_TEXT" ]; then printf '%s\n' "$HINT_TEXT" >&2
        elif [ -s "$DOCTOR_OUT" ]; then sed 's/^/  - /' "$DOCTOR_OUT" >&2
        fi
        [ ! -s "$DOCTOR_ERR" ] || sed 's/^/  - /' "$DOCTOR_ERR" >&2
        if maybe_add_video_group "$DOCTOR_OUT" "$DOCTOR_ERR"; then
            die "Cua doctor exited $DOCTOR_RC. Video access was repaired; sign out/in once, then rerun install.sh."
        fi
        die "Cua doctor exited $DOCTOR_RC. Resolve the hints above, then rerun install.sh."
    fi
    ok "cua-driver doctor"

    HEALTH_OUT="$STATE/cua-health.json"
    HEALTH_RC=0
    "$PRIMARY/scripts/cua-health.py" --driver "$CUA" >"$HEALTH_OUT.tmp" || HEALTH_RC=$?
    [ -s "$HEALTH_OUT.tmp" ] || die "Cua health_report produced no result"
    chmod 600 "$HEALTH_OUT.tmp"; mv "$HEALTH_OUT.tmp" "$HEALTH_OUT"
    case "$HEALTH_RC" in
        0) ok "Cua health_report: ok" ;;
        30) die "Cua health_report is degraded. Inspect: $HEALTH_OUT" ;;
        40) die "Cua health_report failed. Inspect: $HEALTH_OUT" ;;
        *) die "Could not obtain Cua health_report. Inspect: $HEALTH_OUT" ;;
    esac

    if $HERMES; then
        hermes computer-use status >/dev/null 2>&1 || die "Hermes cannot see the installed Cua Driver"
        ok "Hermes sees Cua Driver; /computer-use is enabled for the next Hermes process/session"
    fi
fi

"$PRIMARY/scripts/profile.sh" refresh --quiet >/dev/null 2>&1 || true

printf '\n'
if $RELOAD_REQUIRED; then
    printf 'READY EXCEPT GNOME HELPER RELOAD\n'
    printf 'Control consent, Cua, observation, and .gwcu support are prepared. Reload/sign out once so GNOME loads the updated WinRects helper.\n'
elif $COMPAT; then
    printf 'INSTALLED FOR NEXT UBUNTU GNOME SESSION\n'
else
    printf 'READY. One-time setup is complete.\n'
    if $HERMES; then
        printf 'Hermes: /computer-use status · /computer-use managed · /computer-use truths · /computer-use consent · /computer-use doctor\n'
    fi
fi
printf '\n'
