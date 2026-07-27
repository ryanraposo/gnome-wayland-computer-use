#!/usr/bin/env bash
set -euo pipefail

SELF="$(cd "$(dirname "$0")" && pwd)"

# ── Inlined from lib/checks.sh (self-contained for curl | bash) ──
check_get_session() {
    local s="${XDG_SESSION_TYPE:-}"
    if [ -z "$s" ]; then
        s=$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Type 2>/dev/null | cut -d= -f2)
    fi
    echo "${s:-unknown}"
}
check_get_desktop() {
    local d="${XDG_CURRENT_DESKTOP:-}"
    if [ -z "$d" ]; then
        d=$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Desktop 2>/dev/null | cut -d= -f2)
    fi
    echo "${d:-unknown}"
}
check_is_atspi_bus_alive() {
    gdbus introspect --session --dest org.a11y.Bus --object-path /org/a11y/bus 2>/dev/null | grep -q "interface org.a11y.Bus"
}
check_get_atspi_socket() {
    echo "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/at-spi/bus"
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
    groups "$USER" 2>/dev/null | grep -q "\binput\b"
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

COMPAT=false; UNATTENDED=false
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

info "Starting GNOME Wayland Computer-Use setup..."

# ── 1. Session & Display Verification ────────────────────────────────────
info "[1/4] Verifying display server environment..."
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
info "[2/4] Enabling GTK/GNOME toolkit accessibility via D-Bus..."
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

if command -v gnome-screenshot &>/dev/null; then
    success "Screenshot capture ready (gnome-screenshot)"
else
    warn "gnome-screenshot not found — install: sudo apt install gnome-screenshot"
fi

# ── 3. Skill Installation ────────────────────────────────────────────────
info "[3/4] Installing agent skill..."
install_skill() {
    local src="$SELF/SKILL.md"
    local name="gnome-wayland-computer-use"
    local dst="${HOME}/.agents/skills/${name}/SKILL.md"
    mkdir -p "$(dirname "$dst")"
    if [ -f "$src" ]; then
        cp "$src" "$dst"
    elif command -v curl &>/dev/null; then
        curl -fsSL -o "$dst" "https://ryanraposo.github.io/gnome-wayland-computer-use/SKILL.md"
    fi
    success "Skill installed → ${dst/$HOME/\~}"

    local hermes_dir="${HOME}/.hermes/skills"
    if [ -d "$hermes_dir" ]; then
        local hdst="${hermes_dir}/${name}/SKILL.md"
        mkdir -p "$(dirname "$hdst")"
        if [ -f "$src" ]; then
            cp "$src" "$hdst"
        else
            curl -fsSL -o "$hdst" "https://ryanraposo.github.io/gnome-wayland-computer-use/SKILL.md"
        fi
        success "Hermes skill installed → ${hdst/$HOME/\~}"
    fi
}
install_skill

# ── 4. Input Permissions & Hardware Emulation ────────────────────────────
info "[4/4] Configuring synthetic input (/dev/uinput + ydotoold)..."
if [ -c /dev/uinput ]; then
    if ! check_is_input_group_member; then
        if $UNATTENDED; then
            warn "User not in 'input' group — skipping (run: sudo usermod -aG input $USER)"
        else
            sudo usermod -aG input "$USER"
            warn "Added $USER to 'input' group. Re-login required for /dev/uinput access."
        fi
    else
        success "User $USER belongs to 'input' group."
    fi
fi

if command -v ydotoold &>/dev/null; then
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
    systemctl --user enable --now ydotoold.service 2>/dev/null || true
    success "ydotoold service configured"
else
    warn "ydotoold not found (PX Rung fallback) — install: sudo apt install ydotool"
fi

echo ""
echo -e "     \e[1mAll done.\e[0m"
echo ""
echo -e "  \e[33mDiagnose:\e[0m      scripts/diagnose.sh"
echo -e "  \e[33mTeardown:\e[0m      scripts/teardown.sh"
echo ""
echo -e "
     ▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
"
