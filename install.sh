#!/usr/bin/env bash
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]:-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
    SELF="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
    SELF=""
fi

# ── Inlined from lib/checks.sh (self-contained for curl | bash) ──
check_get_session() {
    local s="${XDG_SESSION_TYPE:-}"
    if [ -z "$s" ]; then
        s=$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Type --value 2>/dev/null || true)
    fi
    printf '%s\n' "${s:-unknown}"
}
check_get_desktop() {
    local d="${XDG_CURRENT_DESKTOP:-}"
    if [ -z "$d" ]; then
        d=$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Desktop --value 2>/dev/null || true)
    fi
    printf '%s\n' "${d:-unknown}"
}
check_is_atspi_bus_alive() {
    gdbus introspect --session --dest org.a11y.Bus --object-path /org/a11y/bus 2>/dev/null | grep -q "interface org.a11y.Bus"
}
check_get_atspi_socket() {
    printf '%s\n' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/at-spi/bus"
}
check_is_atspi_socket_exists() {
    [ -S "$(check_get_atspi_socket)" ]
}
check_start_atspi_service() {
    systemctl --user start at-spi-bus-launcher.service 2>/dev/null || {
        /usr/libexec/at-spi-bus-launcher --launch-immediately 2>/dev/null &
        disown
    }
    for _ in 1 2 3; do
        check_is_atspi_socket_exists && return 0
        sleep 1
    done
    return 1
}
check_is_input_group_member() {
    id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx input
}

info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
success() { echo -e "\e[32m[OK]\e[0m $*"; }
error()   { echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

echo -e "
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"

COMPAT=false; UNATTENDED=false; SESSION_RELOAD_NEEDED=false
TARGET_USER="${SUDO_USER:-${USER:-$(id -un)}}"
UINPUT_DEVICE="${GNOME_WAYLAND_UINPUT_DEVICE:-/dev/uinput}"
for arg in "$@"; do
    case "$arg" in
        --compat) COMPAT=true ;;
        --unattended) UNATTENDED=true ;;
        --help|-h)
            echo "Usage: install.sh [--compat] [--unattended]"
            echo "  --compat      Install without requiring Wayland/GNOME session"
            echo "  --unattended  Skip interactive prompts (for curl | bash)"
            exit 0 ;;
    esac
done
if [ ! -t 0 ] && ! $UNATTENDED; then
    UNATTENDED=true
fi

info "Starting GNOME Wayland Computer-Use setup for Hermes..."

# ── 1. Session & Display Verification ────────────────────────────────────
info "[1/5] Verifying display server environment..."
SESSION=$(check_get_session)
DESKTOP=$(check_get_desktop)

if [ "$SESSION" != "wayland" ]; then
    if $COMPAT; then
        info "Session: $SESSION (compat mode, continuing)"
    else
        warn "Session: $SESSION (expected wayland). Some features may not work."
    fi
else
    success "Active Wayland session detected."
fi

if [[ "$DESKTOP" != *"GNOME"* ]]; then
    if $COMPAT; then
        info "Desktop: $DESKTOP (compat mode, continuing)"
    else
        warn "Desktop: $DESKTOP — some features expect GNOME."
    fi
else
    success "Desktop environment: GNOME"
fi

command -v gsettings &>/dev/null || error "gsettings not found"

# ── 2. AT-SPI D-Bus Accessibility ────────────────────────────────────────
info "[2/5] Enabling GTK/GNOME toolkit accessibility via D-Bus..."
gsettings set org.gnome.desktop.interface toolkit-accessibility true
success "toolkit-accessibility enabled (AX Rung primary path)"

if check_is_atspi_bus_alive; then
    success "AT-SPI2 D-Bus reachable (org.a11y.Bus)"
elif check_start_atspi_service; then
    success "AT-SPI2 D-Bus started (socket at $(check_get_atspi_socket))"
else
    sock=$(check_get_atspi_socket)
    warn "AT-SPI2 D-Bus not reachable — start manually: systemctl --user start at-spi-bus-launcher.service"
    warn "  Expected socket: $sock"
fi

missing_packages=()
command -v ydotool &>/dev/null || missing_packages+=(ydotool)
SYSTEM_PYTHON="/usr/bin/python3"
if [ ! -x "$SYSTEM_PYTHON" ]; then
    SYSTEM_PYTHON="$(command -v python3 2>/dev/null || true)"
fi
if [ -z "$SYSTEM_PYTHON" ] ||
   ! "$SYSTEM_PYTHON" -c "import gi; gi.require_version('Gio','2.0'); gi.require_version('Gst','1.0'); from gi.repository import Gio,Gst" 2>/dev/null; then
    missing_packages+=(python3-gi gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0)
fi
command -v gst-inspect-1.0 &>/dev/null || missing_packages+=(gstreamer1.0-tools)
if ! gst-inspect-1.0 pipewiresrc &>/dev/null; then
    missing_packages+=(gstreamer1.0-pipewire)
fi
if ! gst-inspect-1.0 pngenc &>/dev/null; then
    missing_packages+=(gstreamer1.0-plugins-good)
fi

if [ "${#missing_packages[@]}" -gt 0 ]; then
    command -v apt-get &>/dev/null || \
        error "This installer currently supports Ubuntu/Debian packages; missing: ${missing_packages[*]}"
    info "Installing Ubuntu capture/input packages: ${missing_packages[*]}"
    sudo apt-get install -y "${missing_packages[@]}" || \
        error "Package installation failed. Ensure Ubuntu's main and universe repositories are enabled."
fi
success "Ubuntu capture stack ready (Screenshot portal + PipeWire + ydotool fallback)"

# ── 3. Skill Installation ────────────────────────────────────────────────
info "[3/5] Installing the Hermes skill bundle..."
NAME="gnome-wayland-computer-use"
PRIMARY_DIR="${HOME}/.agents/skills/${NAME}"
HERMES_HOME="${HERMES_HOME:-${HOME}/.hermes}"
HERMES_DIR="${HERMES_HOME}/skills/computer-use"
LEGACY_HERMES_DIR="${HERMES_HOME}/skills/${NAME}"
BASE_URL="https://ryanraposo.github.io/gnome-wayland-computer-use"
MANAGED_MARKER=".gnome-wayland-computer-use-managed"
BACKUP_ROOT="${HERMES_HOME}/backups/gnome-wayland-computer-use"
BACKUP_MANIFEST="${BACKUP_ROOT}/manifest.tsv"
BACKUP_BATCH=""
SOUL_FILE="${HERMES_HOME}/SOUL.md"
SOUL_START="<!-- gnome-wayland-computer-use:start -->"
SOUL_END="<!-- gnome-wayland-computer-use:end -->"
SOUL_CREATED_MARKER="${BACKUP_ROOT}/soul-created-by-installer"

archive_hermes_skill() {
    local src="$1"
    local reason="$2"
    local relative dst

    [ -d "$src" ] || return 0
    if [ -z "$BACKUP_BATCH" ]; then
        BACKUP_BATCH="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)-$$"
        mkdir -p "$BACKUP_BATCH"
    fi
    relative="${src#"${HERMES_HOME}/skills/"}"
    dst="${BACKUP_BATCH}/${relative}"
    mkdir -p "$(dirname "$dst")"
    mv "$src" "$dst"
    printf '%s\t%s\n' "$src" "$dst" >> "$BACKUP_MANIFEST"
    warn "Archived ${src/$HOME/\~} (${reason}); teardown can restore it"
}

is_conflicting_screenshot_skill() {
    local skill_file="$1"
    local skill_dir
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

    grep -qiE '(^|[^[:alnum:]_-])(grim|gnome-screenshot|slurp)([^[:alnum:]_-]|$)|org\.gnome\.Shell\.Screenshot' \
        "$skill_file"
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
## Ubuntu GNOME Wayland desktop capture

This instruction is always active. For every request to capture the desktop,
wallpaper, or desktop icons, do not call
`computer_use` first and do not search the current repository for utilities.
Immediately run this exact terminal workflow:

```bash
HERMES_SKILLS_HOME="${HERMES_HOME:-$HOME/.hermes}"
"$HERMES_SKILLS_HOME/skills/computer-use/scripts/capture.sh" --media
```

The helper emits the `MEDIA:` attachment line itself. Preserve that line in the
response. Do not analyze or describe the screenshot unless the user asks. Its
primary compositor path captures the wallpaper/icons layer without changing
focus, workspace, or window state. Its compatibility path briefly shows the
desktop, captures it, restores the windows, and verifies restoration.
For "capture my screen" or "capture what I am looking at", add `--screen`; that
mode includes visible windows. Never use `--screen` for a desktop request.
Never improvise with `computer_use(app="screen")`, `gnome-screenshot`, `grim`,
`slurp`, ImageMagick `import`, or raw GNOME screenshot D-Bus calls.
SOUL
        printf '%s\n' "$SOUL_END"
        if [ -s "$clean" ]; then
            printf '\n'
            cat "$clean"
        fi
    } > "$next"
    chmod 600 "$next"
    mv "$next" "$SOUL_FILE"
    rm -f "$clean"
    success "Hermes desktop-capture routing activated in ${SOUL_FILE/$HOME/\~}"
}

install_bundle() {
    local dst="$1"
    local skill_source="${2:-SKILL.md}"
    local files=(
        "lib/checks.sh"
        "scripts/capture.sh"
        "scripts/diagnose.sh"
        "scripts/serve.sh"
        "scripts/teardown.sh"
        "gnome-shell-extension/extension.js"
        "gnome-shell-extension/metadata.json"
    )
    local file

    mkdir -p "$dst/lib" "$dst/scripts" "$dst/gnome-shell-extension"
    if [ -n "$SELF" ] && [ -f "$SELF/$skill_source" ]; then
        cp "$SELF/$skill_source" "$dst/SKILL.md"
    else
        command -v curl &>/dev/null || error "curl is required for remote installation"
        curl -fsSL --retry 3 -o "$dst/SKILL.md" "$BASE_URL/$skill_source" || \
            error "Could not download $skill_source"
    fi
    for file in "${files[@]}"; do
        if [ -n "$SELF" ] && [ -f "$SELF/$file" ]; then
            cp "$SELF/$file" "$dst/$file"
        else
            command -v curl &>/dev/null || error "curl is required for remote installation"
            curl -fsSL --retry 3 -o "$dst/$file" "$BASE_URL/$file" || \
                error "Could not download $file"
        fi
    done
    chmod +x "$dst/scripts/"*.sh
    : > "$dst/$MANAGED_MARKER"
}

install_skill() {
    install_bundle "$PRIMARY_DIR"

    if [ -d "$HERMES_DIR" ] && [ ! -f "$HERMES_DIR/$MANAGED_MARKER" ]; then
        archive_hermes_skill "$HERMES_DIR" "pre-existing computer-use skill"
    fi
    install_bundle "$HERMES_DIR" "hermes/SKILL.md"

    if [ -d "$LEGACY_HERMES_DIR" ] &&
       grep -q '^name: gnome-wayland-computer-use$' "$LEGACY_HERMES_DIR/SKILL.md" 2>/dev/null; then
        rm -rf "$LEGACY_HERMES_DIR"
    fi

    local skill_file
    local -a conflicting_skills=()
    while IFS= read -r -d '' skill_file; do
        [ "$(dirname "$skill_file")" = "$HERMES_DIR" ] && continue
        if is_conflicting_screenshot_skill "$skill_file"; then
            conflicting_skills+=("$(dirname "$skill_file")")
        fi
    done < <(find "${HERMES_HOME}/skills" -type f -name SKILL.md -print0 2>/dev/null)
    for skill_file in "${conflicting_skills[@]}"; do
        [ -d "$skill_file" ] || continue
        archive_hermes_skill "$skill_file" "conflicting GNOME Wayland screenshot instructions"
    done

    success "Hermes computer-use override installed → ${HERMES_DIR/$HOME/\~}"
}

install_capture_extension() {
    local uuid="desktop-capture@gnome-wayland-computer-use"
    local extension_dir="${HOME}/.local/share/gnome-shell/extensions/${uuid}"
    local enabled updated

    mkdir -p "$extension_dir"
    cp "$PRIMARY_DIR/gnome-shell-extension/extension.js" "$extension_dir/extension.js"
    cp "$PRIMARY_DIR/gnome-shell-extension/metadata.json" "$extension_dir/metadata.json"

    enabled=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || true)
    [ -n "$enabled" ] || enabled='[]'
    if [[ "$enabled" != *"'$uuid'"* ]] && [[ "$enabled" != *"\"$uuid\""* ]]; then
        updated=$("$SYSTEM_PYTHON" - "$enabled" "$uuid" <<'PY'
import ast
import sys

items = ast.literal_eval(sys.argv[1])
if sys.argv[2] not in items:
    items.append(sys.argv[2])
print(repr(items))
PY
)
        gsettings set org.gnome.shell enabled-extensions "$updated"
    fi

    if command -v gnome-extensions >/dev/null 2>&1; then
        if gnome-extensions enable "$uuid" 2>/dev/null; then
            success "Focus-free GNOME desktop-layer capture extension enabled"
        else
            SESSION_RELOAD_NEEDED=true
            warn "Desktop capture extension queued; sign out of the GNOME session and sign back in once to load it"
        fi
    else
        warn "gnome-extensions not found; enable $uuid after installing GNOME Shell tools"
    fi
}

install_skill
install_capture_extension
install_soul_routing
info "Desktop capture uses the compositor without changing focus or window state."
info "Compatibility capture briefly toggles Show Desktop, captures, then restores it."

# ── 4. Input Permissions & Hardware Emulation ────────────────────────────
info "[4/5] Configuring synthetic input (/dev/uinput + ydotoold)..."
if [ ! -c "$UINPUT_DEVICE" ]; then
    sudo modprobe uinput 2>/dev/null || warn "Could not load the uinput kernel module"
fi
if [ ! -c "$UINPUT_DEVICE" ]; then
    error "/dev/uinput is unavailable after loading the uinput module"
else
    if ! check_is_input_group_member; then
        sudo usermod -aG input "$TARGET_USER"
        SESSION_RELOAD_NEEDED=true
        warn "Added $TARGET_USER to the input group; the same GNOME sign-out/sign-in makes it effective"
    else
        success "User $TARGET_USER belongs to the input group"
    fi

    UDEV_RULE="/etc/udev/rules.d/80-gnome-wayland-computer-use.rules"
    UDEV_RULE_CONTENT='KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"'
    if [ -f "$UDEV_RULE" ] && grep -Fxq "$UDEV_RULE_CONTENT" "$UDEV_RULE"; then
        success "uinput access rule already configured"
    else
        printf '%s\n' "$UDEV_RULE_CONTENT" | sudo tee "$UDEV_RULE" >/dev/null
        sudo udevadm control --reload-rules
        sudo udevadm trigger --name-match=uinput 2>/dev/null || true
        success "uinput access rule installed"
    fi
fi

if command -v ydotoold &>/dev/null; then
    systemctl --user daemon-reload
    if systemctl --user cat ydotool.service &>/dev/null; then
        systemctl --user enable --now ydotool.service
        success "Ubuntu ydotool.service enabled and running"
    else
        mkdir -p "$HOME/.config/systemd/user"
        cat << 'SERVICE' > "$HOME/.config/systemd/user/ydotoold.service"
[Unit]
Description=ydotool uinput daemon
[Service]
Type=simple
ExecStart=/usr/bin/env ydotoold
Restart=on-failure
RestartSec=2s
[Install]
WantedBy=default.target
SERVICE
        systemctl --user daemon-reload
        systemctl --user enable --now ydotoold.service
        success "ydotoold.service enabled and running"
    fi
else
    error "ydotoold is missing after package installation"
fi

# ── 5. Hermes computer_use backend ───────────────────────────────────────
info "[5/5] Connecting Hermes computer_use..."
command -v hermes &>/dev/null || error "Hermes is not on PATH"
if ! command -v cua-driver &>/dev/null; then
    info "Installing Hermes's computer_use driver..."
    hermes computer-use install || error "Hermes could not install cua-driver"
fi
command -v cua-driver &>/dev/null || error "cua-driver is still not on PATH"
cua-driver telemetry disable &>/dev/null || true

mkdir -p "$HOME/.config/systemd/user"
cat << 'SERVICE' > "$HOME/.config/systemd/user/gnome-wayland-computer-use.service"
[Unit]
Description=Hermes computer_use backend for GNOME Wayland
After=graphical-session.target
PartOf=graphical-session.target

[Service]
Type=simple
Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1
ExecStart=%h/.agents/skills/gnome-wayland-computer-use/scripts/serve.sh
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=graphical-session.target
SERVICE

systemctl --user import-environment \
    DISPLAY WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE DBUS_SESSION_BUS_ADDRESS 2>/dev/null || true
systemctl --user daemon-reload
systemctl --user enable gnome-wayland-computer-use.service
systemctl --user restart gnome-wayland-computer-use.service
backend_ready=false
for _ in 1 2 3 4 5 6 7 8 9 10; do
    if cua-driver status &>/dev/null; then
        backend_ready=true
        break
    fi
    sleep 1
done
if $backend_ready; then
    success "Hermes computer_use backend enabled and running"
else
    error "Hermes computer_use backend did not start. Inspect: journalctl --user -u gnome-wayland-computer-use.service"
fi

echo ""
echo -e "     \e[1mAll done.\e[0m"
echo ""
echo -e "  \e[33mDiagnose:\e[0m      ${HERMES_DIR}/scripts/diagnose.sh"
if $SESSION_RELOAD_NEEDED; then
    echo -e "  \e[33mNext:\e[0m          Sign out of the GNOME session and sign back in once, then start a new Hermes session"
else
    echo -e "  \e[33mNext:\e[0m          Start a new Hermes session and ask it to use computer_use"
fi
echo ""
echo -e "
     ▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"
