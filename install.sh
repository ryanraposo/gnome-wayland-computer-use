#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
    SELF="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
    SELF=""
fi

info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
success() { echo -e "\e[32m[OK]\e[0m $*"; }
error()   { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

as_root() {
    if command -v pkexec >/dev/null 2>&1; then
        pkexec "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        error "A graphical PolicyKit helper (pkexec) or sudo is required for: $*"
    fi
}

check_get_session() {
    local s="${XDG_SESSION_TYPE:-}"
    [ -n "$s" ] || s=$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Type --value 2>/dev/null || true)
    printf '%s\n' "${s:-unknown}"
}
check_get_desktop() {
    local d="${XDG_CURRENT_DESKTOP:-}"
    [ -n "$d" ] || d=$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Desktop --value 2>/dev/null || true)
    printf '%s\n' "${d:-unknown}"
}
check_is_atspi_bus_alive() {
    gdbus introspect --session --dest org.a11y.Bus --object-path /org/a11y/bus 2>/dev/null | grep -q 'interface org.a11y.Bus'
}
check_get_atspi_socket() {
    printf '%s\n' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/at-spi/bus"
}
check_start_atspi_service() {
    systemctl --user start at-spi-bus-launcher.service 2>/dev/null || {
        /usr/libexec/at-spi-bus-launcher --launch-immediately 2>/dev/null &
        disown
    }
    for _ in {1..30}; do [ -S "$(check_get_atspi_socket)" ] && return 0; sleep 0.1; done
    return 1
}

echo -e "
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"

COMPAT=false
UNATTENDED=false
SESSION_RELOAD_NEEDED=false
RUNTIME_MODE=auto
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
UINPUT_DEVICE="${GNOME_WAYLAND_UINPUT_DEVICE:-/dev/uinput}"
SYSTEM_PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"

for arg in "$@"; do
    case "$arg" in
        --compat) COMPAT=true ;;
        --unattended) UNATTENDED=true ;;
        --hermes)
            [ "$RUNTIME_MODE" != agent ] || error "--hermes and --agent-only cannot be combined"
            RUNTIME_MODE=hermes
            ;;
        --agent-only)
            [ "$RUNTIME_MODE" != hermes ] || error "--hermes and --agent-only cannot be combined"
            RUNTIME_MODE=agent
            ;;
        --help|-h)
            cat <<'HELP'
Usage: install.sh [--compat] [--unattended] [--hermes|--agent-only]
  --compat      Install without requiring an active GNOME Wayland session
  --unattended  Mark piped/automated execution (privilege prompts may remain)
  --hermes      Require and configure Hermes
  --agent-only  Install the shared Agent Skills stack without Hermes
HELP
            exit 0
            ;;
        *) error "Unknown option: $arg (run with --help for usage)" ;;
    esac
done

if [ ! -t 0 ] && ! $UNATTENDED; then UNATTENDED=true; fi
[ "$EUID" -ne 0 ] || error "Run this installer as the logged-in desktop user, not with sudo"

HERMES_ENABLED=false
case "$RUNTIME_MODE" in
    auto) command -v hermes &>/dev/null && HERMES_ENABLED=true || true ;;
    hermes)
        command -v hermes &>/dev/null || error "Hermes was explicitly requested but is not on PATH"
        HERMES_ENABLED=true
        ;;
    agent) ;;
esac

info "Starting GNOME Wayland Computer-Use setup..."

# ── 1. Session ───────────────────────────────────────────────────────────
info "[1/5] Verifying desktop session..."
SESSION=$(check_get_session)
DESKTOP=$(check_get_desktop)
if [ "$SESSION" != wayland ]; then
    $COMPAT && info "Session: $SESSION (compat mode)" || error "Session: $SESSION (expected wayland). Use --compat only intentionally."
else
    success "Active Wayland session detected"
fi
if [[ "$DESKTOP" != *GNOME* ]]; then
    $COMPAT && info "Desktop: $DESKTOP (compat mode)" || error "Desktop: $DESKTOP (expected GNOME). Use --compat only intentionally."
else
    success "Desktop environment: GNOME"
fi
command -v gsettings &>/dev/null || error "gsettings not found"

# ── 2. Accessibility + native capture dependencies ──────────────────────
info "[2/5] Preparing accessibility and native capture..."
gsettings set org.gnome.desktop.interface toolkit-accessibility true
if check_is_atspi_bus_alive; then
    success "AT-SPI2 D-Bus reachable"
elif check_start_atspi_service; then
    success "AT-SPI2 D-Bus started"
else
    warn "AT-SPI2 D-Bus did not become reachable; semantic UI control may be degraded"
fi

if [ ! -x "$SYSTEM_PYTHON" ]; then
    SYSTEM_PYTHON="$(command -v python3 2>/dev/null || true)"
fi

missing_packages=()
add_pkg() {
    local pkg="$1" existing
    for existing in "${missing_packages[@]:-}"; do [ "$existing" = "$pkg" ] && return 0; done
    missing_packages+=("$pkg")
}

command -v ydotool &>/dev/null || add_pkg ydotool
if [ -z "$SYSTEM_PYTHON" ] ||
   ! "$SYSTEM_PYTHON" -c "import gi; gi.require_version('Gio','2.0'); from gi.repository import Gio" 2>/dev/null; then
    add_pkg python3-gi
fi
if [ -z "$SYSTEM_PYTHON" ] ||
   ! "$SYSTEM_PYTHON" -c "import gi; gi.require_version('Gst','1.0'); from gi.repository import Gst" 2>/dev/null; then
    add_pkg python3-gi
    add_pkg gir1.2-gstreamer-1.0
fi
command -v gst-inspect-1.0 &>/dev/null || add_pkg gstreamer1.0-tools
if command -v gst-inspect-1.0 &>/dev/null; then
    gst-inspect-1.0 pipewiresrc &>/dev/null || add_pkg gstreamer1.0-pipewire
    gst-inspect-1.0 pngenc &>/dev/null || add_pkg gstreamer1.0-plugins-good
else
    add_pkg gstreamer1.0-pipewire
    add_pkg gstreamer1.0-plugins-good
fi

if [ "${#missing_packages[@]}" -gt 0 ]; then
    command -v apt-get &>/dev/null || error "Ubuntu/Debian package manager required for: ${missing_packages[*]}"
    info "Installing capture/input packages: ${missing_packages[*]}"
    as_root apt-get install -y "${missing_packages[@]}" || error "Package installation failed"
fi
success "Native capture stack prepared (XDG ScreenCast + PipeWire; Screenshot recovery)"

# ── 3. Skill bundle and migration ────────────────────────────────────────
info "[3/5] Installing the computer-use skill bundle..."
NAME="gnome-wayland-computer-use"
PRIMARY_DIR="$HOME/.agents/skills/$NAME"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_DIR="$HERMES_HOME/skills/computer-use"
LEGACY_HERMES_DIR="$HERMES_HOME/skills/$NAME"
BASE_URL="https://ryanraposo.github.io/gnome-wayland-computer-use"
MANAGED_MARKER=".gnome-wayland-computer-use-managed"
HERMES_INTEGRATION_MARKER=".hermes-integration"
BACKUP_ROOT="$HERMES_HOME/backups/gnome-wayland-computer-use"
BACKUP_MANIFEST="$BACKUP_ROOT/manifest.tsv"
BACKUP_BATCH=""
SOUL_FILE="$HERMES_HOME/SOUL.md"
SOUL_START='<!-- gnome-wayland-computer-use:start -->'
SOUL_END='<!-- gnome-wayland-computer-use:end -->'
SOUL_CREATED_MARKER="$BACKUP_ROOT/soul-created-by-installer"

remove_legacy_capture_extension() {
    local uuid='desktop-capture@gnome-wayland-computer-use'
    local extension_dir="$HOME/.local/share/gnome-shell/extensions/$uuid"
    local enabled updated

    command -v gnome-extensions &>/dev/null && gnome-extensions disable "$uuid" 2>/dev/null || true
    rm -rf "$extension_dir"

    enabled=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)
    if [ -n "$enabled" ] && { [[ "$enabled" == *"'$uuid'"* ]] || [[ "$enabled" == *"\"$uuid\""* ]]; }; then
        [ -n "$SYSTEM_PYTHON" ] || return 0
        updated=$("$SYSTEM_PYTHON" - "$enabled" "$uuid" <<'PY'
import ast, sys
try:
    items = ast.literal_eval(sys.argv[1])
except Exception:
    raise SystemExit(1)
print(repr([item for item in items if item != sys.argv[2]]))
PY
) || return 0
        gsettings set org.gnome.shell enabled-extensions "$updated" 2>/dev/null || true
    fi
}

archive_hermes_skill() {
    local src="$1" reason="$2" relative dst
    [ -d "$src" ] || return 0
    if [ -z "$BACKUP_BATCH" ]; then
        BACKUP_BATCH="$BACKUP_ROOT/$(date +%Y%m%d-%H%M%S)-$$"
        mkdir -p "$BACKUP_BATCH"
    fi
    relative="${src#"$HERMES_HOME/skills/"}"
    dst="$BACKUP_BATCH/$relative"
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
    printf '%s\t%s\n' "$src" "$dst" >> "$BACKUP_MANIFEST"
    warn "Archived ${src/$HOME/\~} ($reason); teardown can restore it"
}

is_conflicting_screenshot_skill() {
    local skill_file="$1" skill_dir
    skill_dir="$(dirname "$skill_file")"
    awk '
        NR == 1 && $0 == "---" { frontmatter = 1; next }
        frontmatter && $0 == "---" { exit }
        frontmatter && tolower($0) ~ /^(name|slug):/ {
            value = tolower($0)
            sub(/^[^:]*:[[:space:]]*/, "", value)
            gsub(/^["'\'']|["'\''][[:space:]]*$/, "", value)
            if (value ~ /screenshot|screen[-_ ]?capture/) found = 1
        }
        END { exit !found }
    ' "$skill_file" || [[ "$(basename "$skill_dir" | tr '[:upper:]' '[:lower:]')" =~ screenshot|screen-capture|screen_capture ]] || return 1
    grep -qiE '(^|[^[:alnum:]_-])(grim|gnome-screenshot|slurp)([^[:alnum:]_-]|$)|org\.gnome\.Shell\.Screenshot' "$skill_file"
}

copy_or_download() {
    local rel="$1" dst="$2"
    if [ -n "$SELF" ] && [ -f "$SELF/$rel" ]; then
        cp "$SELF/$rel" "$dst"
    else
        command -v curl &>/dev/null || error "curl is required for remote installation"
        curl -fsSL --retry 3 -o "$dst" "$BASE_URL/$rel" || error "Could not download $rel"
    fi
}

install_bundle() {
    local dst="$1" rel
    local files=(
        VERSION
        references/skill-ux-contract.md
        lib/checks.sh
        scripts/app-identity.sh
        scripts/capture.sh
        scripts/check-update.sh
        scripts/diagnose.sh
        scripts/serve.sh
        scripts/teardown.sh
    )
    mkdir -p "$dst/references" "$dst/lib" "$dst/scripts"
    rm -rf "$dst/gnome-shell-extension"
    copy_or_download SKILL.md "$dst/SKILL.md"
    for rel in "${files[@]}"; do
        mkdir -p "$(dirname "$dst/$rel")"
        copy_or_download "$rel" "$dst/$rel"
    done
    chmod +x "$dst/scripts/"*.sh
    : > "$dst/$MANAGED_MARKER"
}

install_openai_payload() {
    local dst="$1"
    mkdir -p "$dst/agents"
    if [ -n "$SELF" ] && [ -f "$SELF/runtimes/openai/SKILL.md" ]; then
        cp "$SELF/runtimes/openai/SKILL.md" "$dst/SKILL.md"
        cp "$SELF/agents/openai.yaml" "$dst/agents/openai.yaml"
    else
        curl -fsSL --retry 3 -o "$dst/SKILL.md" "$BASE_URL/runtimes/openai/SKILL.md" || error "Could not download OpenAI skill"
        curl -fsSL --retry 3 -o "$dst/agents/openai.yaml" "$BASE_URL/agents/openai.yaml" || error "Could not download OpenAI skill metadata"
    fi
}

install_shared_skill() {
    install_bundle "$PRIMARY_DIR"
    install_openai_payload "$PRIMARY_DIR"
    success "Portable Agent Skill installed → ${PRIMARY_DIR/$HOME/\~}"
}

install_hermes_skill() {
    if [ -d "$HERMES_DIR" ] && [ ! -f "$HERMES_DIR/$MANAGED_MARKER" ]; then
        archive_hermes_skill "$HERMES_DIR" 'pre-existing computer-use skill'
    fi
    install_bundle "$HERMES_DIR"

    if [ -d "$LEGACY_HERMES_DIR" ] && grep -q '^name: gnome-wayland-computer-use$' "$LEGACY_HERMES_DIR/SKILL.md" 2>/dev/null; then
        archive_hermes_skill "$LEGACY_HERMES_DIR" 'legacy managed skill location'
    fi

    local skill_file dir
    local -a conflicts=()
    while IFS= read -r -d '' skill_file; do
        dir="$(dirname "$skill_file")"
        [ "$dir" = "$HERMES_DIR" ] && continue
        is_conflicting_screenshot_skill "$skill_file" && conflicts+=("$dir") || true
    done < <(find "$HERMES_HOME/skills" -type f -name SKILL.md -print0 2>/dev/null)
    for dir in "${conflicts[@]}"; do [ -d "$dir" ] && archive_hermes_skill "$dir" 'conflicting GNOME Wayland screenshot instructions'; done

    : > "$PRIMARY_DIR/$HERMES_INTEGRATION_MARKER"
    success "Hermes computer-use override installed → ${HERMES_DIR/$HOME/\~}"
}

install_soul_routing() {
    local clean next
    mkdir -p "$HERMES_HOME" "$BACKUP_ROOT"
    clean=$(mktemp "${SOUL_FILE}.clean.XXXXXX")
    next=$(mktemp "${SOUL_FILE}.next.XXXXXX")

    if [ -f "$SOUL_FILE" ]; then
        awk -v start="$SOUL_START" -v end="$SOUL_END" '
            $0 == start { managed = 1; next }
            $0 == end { managed = 0; next }
            !managed { print }
        ' "$SOUL_FILE" > "$clean"
    else
        : > "$clean"
        : > "$SOUL_CREATED_MARKER"
    fi

    {
        printf '%s\n' "$SOUL_START"
        cat <<'SOUL'
## Ubuntu GNOME Wayland screen capture

For requests to capture the desktop, screen, or what is currently visible, run:

```bash
HERMES_SKILLS_HOME="${HERMES_HOME:-$HOME/.hermes}"
"$HERMES_SKILLS_HOME/skills/computer-use/scripts/capture.sh" --media --screen
```

Preserve the emitted `MEDIA:` line. The hot path is XDG ScreenCast + PipeWire
with persistent restore permission when supported. `--desktop` is a compatibility
alias for the visible display. Do not install or depend on a GNOME Shell capture
or window-geometry helper.
SOUL
        printf '%s\n' "$SOUL_END"
        [ ! -s "$clean" ] || { printf '\n'; cat "$clean"; }
    } > "$next"
    chmod 600 "$next"
    mv "$next" "$SOUL_FILE"
    rm -f "$clean"
    success "Hermes screen-capture routing activated"
}

remove_legacy_capture_extension
install_shared_skill
if $HERMES_ENABLED; then
    install_hermes_skill
    install_soul_routing
fi
success "Project Shell capture extension retired; native portal capture installed"

# ── 4. Input recovery ────────────────────────────────────────────────────
info "[4/5] Configuring explicit input recovery..."
if [ ! -c "$UINPUT_DEVICE" ]; then as_root modprobe uinput 2>/dev/null || warn "Could not load uinput"; fi
[ -c "$UINPUT_DEVICE" ] || error "/dev/uinput is unavailable"

if ! id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx input; then
    as_root usermod -aG input "$TARGET_USER"
    SESSION_RELOAD_NEEDED=true
    warn "Added $TARGET_USER to input group; sign out/in once for that fallback permission"
else
    success "User $TARGET_USER belongs to input group"
fi

UDEV_RULE='/etc/udev/rules.d/80-gnome-wayland-computer-use.rules'
UDEV_RULE_CONTENT='KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"'
if [ -f "$UDEV_RULE" ] && grep -Fxq "$UDEV_RULE_CONTENT" "$UDEV_RULE"; then
    success "uinput access rule already configured"
else
    rule_tmp=$(mktemp)
    printf '%s\n' "$UDEV_RULE_CONTENT" > "$rule_tmp"
    as_root install -m 0644 "$rule_tmp" "$UDEV_RULE"
    rm -f "$rule_tmp"
    as_root udevadm control --reload-rules
    as_root udevadm trigger --name-match=uinput 2>/dev/null || true
    success "uinput access rule installed"
fi

if command -v ydotoold &>/dev/null; then
    mkdir -p "$HOME/.config/systemd/user"
    if systemctl --user cat ydotool.service &>/dev/null; then
        systemctl --user enable --now ydotool.service
    else
        cat > "$HOME/.config/systemd/user/ydotoold.service" <<'SERVICE'
[Unit]
Description=ydotool uinput daemon
[Service]
Type=simple
ExecStart=/usr/bin/env ydotoold
Restart=on-failure
RestartSec=250ms
[Install]
WantedBy=default.target
SERVICE
        systemctl --user daemon-reload
        systemctl --user enable --now ydotoold.service
    fi
    success "ydotool fallback ready"
else
    error "ydotoold is missing after package installation"
fi

# ── 5. Runtime ───────────────────────────────────────────────────────────
if $HERMES_ENABLED; then
    info "[5/5] Connecting Hermes computer_use..."
    if ! command -v cua-driver &>/dev/null; then
        hermes computer-use install || error "Hermes could not install cua-driver"
    fi
    command -v cua-driver &>/dev/null || error "cua-driver is still not on PATH"
    cua-driver telemetry disable &>/dev/null || true

    mkdir -p "$HOME/.config/systemd/user"
    cat > "$HOME/.config/systemd/user/gnome-wayland-computer-use.service" <<'SERVICE'
[Unit]
Description=cua-driver backend for GNOME Wayland computer use
After=graphical-session.target
PartOf=graphical-session.target
[Service]
Type=simple
Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1
ExecStart=%h/.agents/skills/gnome-wayland-computer-use/scripts/serve.sh
Restart=on-failure
RestartSec=250ms
TimeoutStopSec=2s
[Install]
WantedBy=graphical-session.target
SERVICE
    systemctl --user import-environment DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
    systemctl --user daemon-reload
    systemctl --user enable gnome-wayland-computer-use.service
    systemctl --user restart gnome-wayland-computer-use.service
    backend_ready=false
    for _ in {1..40}; do cua-driver status &>/dev/null && { backend_ready=true; break; }; sleep 0.1; done
    $backend_ready || error "Hermes computer_use backend did not start"
    success "Hermes computer_use backend ready"
else
    info "[5/5] Finalizing shared agent integration..."
    success "Shared GNOME host stack ready"
fi

echo ""
echo -e "     \e[1mAll done.\e[0m"
echo ""
echo -e "  \e[33mDiagnose:\e[0m      $PRIMARY_DIR/scripts/diagnose.sh"
echo -e "  \e[33mCapture:\e[0m       $PRIMARY_DIR/scripts/capture.sh --timing --screen /tmp/screen.png"
if $SESSION_RELOAD_NEEDED; then
    echo -e "  \e[33mNext:\e[0m          Sign out of GNOME and back in once for input-group fallback access"
elif $HERMES_ENABLED; then
    echo -e "  \e[33mNext:\e[0m          Start a new Hermes session; first screen capture may ask for monitor permission"
else
    echo -e "  \e[33mNext:\e[0m          Start a new agent session; first screen capture may ask for monitor permission"
fi

echo -e "
     ▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"
