#!/usr/bin/env bash
# install.sh — install the Ubuntu GNOME integration around Cua Driver.
set -euo pipefail

NAME="gnome-wayland-computer-use"
VERSION="2.3.0"
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
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

COMPAT=false
UNATTENDED=false
HERMES_MODE=auto
for arg in "$@"; do
    case "$arg" in
        --compat) COMPAT=true ;;
        --unattended) UNATTENDED=true ;;
        --hermes) HERMES_MODE=require ;;
        --agent-only) HERMES_MODE=skip ;;
        --help|-h)
            cat <<'HELP'
Usage: install.sh [--compat] [--unattended] [--hermes|--agent-only]
  --hermes      require and install the Hermes skill integration
  --agent-only  skip Hermes-specific files; Cua Driver is still the control authority
  --compat      install files without requiring a live GNOME Wayland session
  --unattended  automated invocation; privilege prompts may still appear
HELP
            exit 0
            ;;
        *) die "Unknown option: $arg" ;;
    esac
done

[ "$EUID" -ne 0 ] || die "Run as the logged-in desktop user, not with sudo"
if [ ! -t 0 ] && ! $UNATTENDED; then UNATTENDED=true; fi

HERMES=false
case "$HERMES_MODE" in
    auto) command -v hermes >/dev/null 2>&1 && HERMES=true || true ;;
    require) command -v hermes >/dev/null 2>&1 || die "--hermes requested but hermes is not on PATH"; HERMES=true ;;
    skip) ;;
esac

printf '\nGNOME WAYLAND COMPUTER USE // CUA-NATIVE\n\n'
info "[1/6] Checking the desktop session"
SESSION=$(session_type)
DESKTOP=$(desktop_name)
if [ "$SESSION" != wayland ] || [[ "$DESKTOP" != *GNOME* ]]; then
    if ! $COMPAT; then die "Expected an active GNOME Wayland session; found session=$SESSION desktop=$DESKTOP"; fi
    warn "Compatibility install: session=$SESSION desktop=$DESKTOP"
else
    ok "GNOME Wayland session"
fi

info "[2/6] Verifying Ubuntu native foundation"
missing=()
add_pkg(){ local p="$1" x; for x in "${missing[@]:-}"; do [ "$x" = "$p" ] && return; done; missing+=("$p"); }
command -v gsettings >/dev/null 2>&1 || add_pkg libglib2.0-bin
command -v gdbus >/dev/null 2>&1 || add_pkg libglib2.0-bin
[ -x /usr/bin/python3 ] || add_pkg python3
pipewire_ready || { add_pkg pipewire; add_pkg wireplumber; }
portal_has ScreenCast || { add_pkg xdg-desktop-portal; add_pkg xdg-desktop-portal-gnome; }
portal_has Screenshot || { add_pkg xdg-desktop-portal; add_pkg xdg-desktop-portal-gnome; }
command -v gst-inspect-1.0 >/dev/null 2>&1 || add_pkg gstreamer1.0-tools
if command -v gst-inspect-1.0 >/dev/null 2>&1; then
    gst-inspect-1.0 pipewiresrc >/dev/null 2>&1 || add_pkg gstreamer1.0-pipewire
    gst-inspect-1.0 pngenc >/dev/null 2>&1 || add_pkg gstreamer1.0-plugins-good
else
    add_pkg gstreamer1.0-pipewire
    add_pkg gstreamer1.0-plugins-good
fi
gi_ready || {
    add_pkg python3-gi
    add_pkg python3-gst-1.0
    add_pkg gir1.2-gstreamer-1.0
    add_pkg gir1.2-gst-plugins-base-1.0
    add_pkg gir1.2-gdkpixbuf-2.0
}
if ! command -v gdbus >/dev/null 2>&1 || \
   ! gdbus introspect --session --dest org.a11y.Bus --object-path /org/a11y/bus >/dev/null 2>&1; then
    add_pkg at-spi2-core
fi

if [ "${#missing[@]}" -gt 0 ]; then
    command -v apt-get >/dev/null 2>&1 || die "Missing Ubuntu packages: ${missing[*]}"
    info "Repairing: ${missing[*]}"
    if ! as_root apt-get install -y "${missing[@]}"; then
        info "Refreshing package metadata and retrying once"
        as_root apt-get update
        as_root apt-get install -y "${missing[@]}" || die "Ubuntu dependency repair failed"
    fi
fi

systemctl --user start pipewire.socket pipewire.service wireplumber.service 2>/dev/null || true
systemctl --user start xdg-desktop-portal.service xdg-desktop-portal-gnome.service 2>/dev/null || true
pipewire_ready || $COMPAT || die "PipeWire is still unavailable after repair"
gi_ready || die "Python GI/GStreamer observation bindings are unavailable after repair"
if ! $COMPAT; then portal_has ScreenCast || die "GNOME ScreenCast portal is unavailable after repair"; fi
ok "PipeWire, portals, GStreamer, Python GI and AT-SPI foundation prepared"

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
mkdir -p "$STATE"; chmod 700 "$STATE" 2>/dev/null || true
# Retire the old claim that GWCU owns Cua's helper. Cua/WinRects are upstream.
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

info "[3/6] Installing Cua Driver"
CUA=$(resolve_cua || true)
CUA_INSTALLED_BY_GWCU=false
if [ -z "$CUA" ]; then
    command -v curl >/dev/null 2>&1 || die "curl is required to install Cua Driver"
    /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)" || die "Cua Driver installer failed"
    export PATH="$HOME/.local/bin:$PATH"
    CUA=$(resolve_cua || true)
    [ -n "$CUA" ] || die "cua-driver is unavailable after the official installer"
    CUA_INSTALLED_BY_GWCU=true
fi
ok "Cua Driver: $CUA"

CUA_HOME="${CUA_DRIVER_HOME:-$HOME/.cua-driver}"
HELPER="$CUA_HOME/packages/current/wayland-helper"
CUA_HELPER_INSTALLER="$HELPER/install.sh"
WINRECTS_UUID='winrects@cua'
WINRECTS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$WINRECTS_UUID"
if [ ! -x "$CUA_HELPER_INSTALLER" ]; then
    command -v curl >/dev/null 2>&1 || die "curl is required to refresh Cua Driver"
    info "Refreshing Cua Driver because the packaged GNOME helper is missing"
    /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)" || die "Cua Driver refresh failed"
    export PATH="$HOME/.local/bin:$PATH"
    CUA=$(resolve_cua || true)
    [ -n "$CUA" ] || die "cua-driver is unavailable after refresh"
fi
[ -x "$CUA_HELPER_INSTALLER" ] || die "Cua's packaged GNOME helper is missing: $CUA_HELPER_INSTALLER"

helper_matches=false
if [ -f "$HELPER/$WINRECTS_UUID/extension.js" ] && [ -f "$WINRECTS_DIR/extension.js" ] && \
   [ -f "$HELPER/$WINRECTS_UUID/metadata.json" ] && [ -f "$WINRECTS_DIR/metadata.json" ] && \
   cmp -s "$HELPER/$WINRECTS_UUID/extension.js" "$WINRECTS_DIR/extension.js" && \
   cmp -s "$HELPER/$WINRECTS_UUID/metadata.json" "$WINRECTS_DIR/metadata.json"; then
    helper_matches=true
fi
helper_was_active=false
if command -v gnome-extensions >/dev/null 2>&1 && \
   gnome-extensions info "$WINRECTS_UUID" 2>/dev/null | grep -q 'State:[[:space:]]*ACTIVE'; then
    helper_was_active=true
fi
helper_changed=false
$helper_matches || helper_changed=true
if ! $helper_matches || ! $helper_was_active; then
    "$CUA_HELPER_INSTALLER" || die "Cua WinRects helper installation failed"
fi
[ -d "$WINRECTS_DIR" ] || die "Cua WinRects was not installed"

helper_active=false
if command -v gnome-extensions >/dev/null 2>&1 && \
   gnome-extensions info "$WINRECTS_UUID" 2>/dev/null | grep -q 'State:[[:space:]]*ACTIVE'; then
    helper_active=true
fi
RELOAD_REQUIRED=false
if ! $helper_changed && $helper_active; then
    ok "Cua GNOME helper current and active"
else
    RELOAD_REQUIRED=true
    warn "Cua GNOME helper installed/updated; one GNOME sign-out/in is required"
fi

info "[4/6] Installing the agent operating layer"
PRIMARY="$HOME/.agents/skills/$NAME"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_SKILL="$HERMES_HOME/skills/computer-use"
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
    for rel in VERSION references/skill-ux-contract.md \
        scripts/app-identity.sh scripts/capture.sh scripts/check-update.sh scripts/diagnose.sh \
        scripts/observe.sh scripts/observer.py scripts/profile.sh scripts/teardown.sh \
        systemd/user/gnome-wayland-computer-use-observer.socket \
        systemd/user/gnome-wayland-computer-use-observer.service; do
        get_file "$rel" "$dst/$rel"
    done
    [ "$(tr -d '[:space:]' < "$dst/VERSION")" = "$VERSION" ] || die "Installer payload version mismatch"
    chmod +x "$dst/scripts/"*.sh "$dst/scripts/observer.py"
    : > "$dst/$MANAGED"
}

install_bundle "$PRIMARY" runtimes/openai/SKILL.md
mkdir -p "$PRIMARY/agents"
get_file agents/openai.yaml "$PRIMARY/agents/openai.yaml"

if $HERMES; then
    install_bundle "$HERMES_SKILL" SKILL.md
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
ok "Agent skill installed"

# Retire project-owned control/recovery machinery from older releases.
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

info "[5/6] Enabling lazy whole-screen observation"
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
    if [ -f "$SOUL" ]; then awk -v s="$START" -v e="$END" '$0==s{m=1;next}$0==e{m=0;next}!m{print}' "$SOUL" >"$clean"; else : >"$clean"; fi
    {
        printf '%s\n' "$START"
        cat <<'SOUL'
## Ubuntu GNOME Wayland computer use

Use Hermes `computer_use` normally; Cua Driver is the control authority for semantics,
pixels, geometry, activation, input delivery, verification, and refusals. For an
explicit whole-screen/desktop observation, use the installed
`gnome-wayland-computer-use/scripts/observe.sh` helper. Do not invent a raw-input
fallback when Cua refuses a delivery shape.
SOUL
        printf '%s\n' "$END"
        [ ! -s "$clean" ] || { printf '\n'; cat "$clean"; }
    } >"$next"
    chmod 600 "$next"; mv "$next" "$SOUL"; rm -f "$clean"
fi

info "[6/6] Verifying installed state"
DOCTOR_RC=0
DOCTOR_OUT="$STATE/cua-doctor.json"
"$CUA" doctor --json >"$DOCTOR_OUT.tmp" 2>/dev/null || DOCTOR_RC=$?
if [ -s "$DOCTOR_OUT.tmp" ]; then chmod 600 "$DOCTOR_OUT.tmp"; mv "$DOCTOR_OUT.tmp" "$DOCTOR_OUT"; else rm -f "$DOCTOR_OUT.tmp"; fi
if [ "$DOCTOR_RC" -ne 0 ] && ! $RELOAD_REQUIRED && ! $COMPAT; then
    die "Cua doctor reports a problem after installation. Run: $CUA doctor"
fi
if $HERMES && ! $COMPAT; then
    hermes computer-use status >/dev/null 2>&1 || die "Hermes cannot see the installed Cua Driver"
fi

python3 - "$STATE/ownership.json" "$PREV_ACCESSIBILITY" "$ACCESSIBILITY_CHANGED" "$CUA_INSTALLED_BY_GWCU" <<'PY'
import json, os, pathlib, sys
p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True,exist_ok=True)
d={
 "schema":"gwcu.ownership.v2",
 "toolkit_accessibility":{"previous":sys.argv[2],"changed":sys.argv[3]=="true"},
 "upstream":{"cua_driver":{"provisioned":sys.argv[4]=="true","owned":False},"winrects":{"owned":False}},
 "user_units":{"observer_socket":True,"observer_service":True},
 "distro_foundation_owned":False,
}
t=p.with_suffix('.tmp'); t.write_text(json.dumps(d,separators=(',',':'))+'\n'); os.chmod(t,0o600); os.replace(t,p)
PY

"$PRIMARY/scripts/profile.sh" refresh --quiet >/dev/null 2>&1 || true

printf '\n'
if $RELOAD_REQUIRED; then
    printf 'READY EXCEPT GNOME PRECISION\n'
    printf 'Sign out of GNOME and back in once. Observation and accessibility are already installed.\n'
elif $COMPAT; then
    printf 'INSTALLED FOR NEXT GNOME WAYLAND SESSION\n'
else
    printf 'READY. Start your agent.\n'
fi
printf '\n'
