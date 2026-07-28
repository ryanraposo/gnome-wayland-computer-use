#!/usr/bin/env bash
# lib/checks.sh — shared validation library for gnome-wayland-computer-use
# Source with: . "$(dirname "$0")/lib/checks.sh"

# ── Styling ──
CK_R='\033[0;31m'; CK_G='\033[0;32m'; CK_Y='\033[1;33m'; CK_N='\033[0m'
check_ok()   { printf "  ${CK_G}✓${CK_N} %s\n" "$*"; }
check_fail() { printf "  ${CK_R}✗${CK_N} %s\n" "$*"; }
check_info() { printf "  ${CK_Y}→${CK_N} %s\n" "$*"; }
check_hr()   { echo "────────────────────────────────────────"; }

CK_SCORE=0; CK_TOTAL=0
check_pass()  { ((CK_SCORE++)) || true; ((CK_TOTAL++)) || true; }
check_xfail() { ((CK_TOTAL++)) || true; }
check_print_summary() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Result: $CK_SCORE / $CK_TOTAL checks passed"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ── Version comparison ──
check_version_ge() {
    [ $# -eq 2 ] || return 2
    [ -n "$1" ] || return 2
    [ -n "$2" ] || return 1
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -1 | grep -qF "$2"
}

# ── Data functions (silent) ──
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

# ── Predicate functions (silent, return 0/1) ──
check_is_wayland()      { [ "$(check_get_session)" = "wayland" ]; }
check_is_gnome()        { [[ "$(check_get_desktop)" == *"GNOME"* ]]; }
check_is_gnome_shell_running() { pgrep -x gnome-shell &>/dev/null; }
check_is_xwayland_running()    { pgrep -x Xwayland &>/dev/null; }

check_is_toolkit_accessibility_enabled() {
    local val
    val=$(gsettings get org.gnome.desktop.interface toolkit-accessibility 2>/dev/null) || return 1
    [ "$val" = "true" ]
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

check_has_uinput_device() { [ -c /dev/uinput ]; }

check_is_input_group_member() {
    id -nG 2>/dev/null | tr ' ' '\n' | grep -qx input
}

check_is_ydotoold_installed()   { command -v ydotoold &>/dev/null; }
check_is_ydotoold_enabled()     {
    systemctl --user is-enabled ydotool.service &>/dev/null ||
        systemctl --user is-enabled ydotoold.service &>/dev/null
}
check_is_ydotoold_running()     {
    systemctl --user is-active ydotool.service &>/dev/null ||
        systemctl --user is-active ydotoold.service &>/dev/null
}
check_is_ydotoold_process_up()  { pgrep -x ydotoold &>/dev/null; }
check_is_cua_driver_installed() { command -v cua-driver &>/dev/null; }
check_is_cua_driver_running()   {
    systemctl --user is-active gnome-wayland-computer-use.service &>/dev/null &&
        timeout 3 cua-driver status &>/dev/null
}

check_is_env_in_bashrc() {
    local var="$1"
    grep -Fq "$var" "$HOME/.bashrc" 2>/dev/null
}

check_is_service_enabled() {
    local name="$1"
    systemctl --user is-enabled "$name" &>/dev/null
}

check_is_service_running() {
    local name="$1"
    systemctl --user is-active "$name" &>/dev/null
}

check_has_systemd_service() {
    local name="$1"
    systemctl --user --type service list-units --all 2>/dev/null | grep -q "$name"
}

check_skill_installed() {
    local name="gnome-wayland-computer-use"
    [ -f "${HOME}/.agents/skills/${name}/SKILL.md" ]
}

check_hermes_skill_installed() {
    local dir="${HERMES_HOME:-$HOME/.hermes}/skills/computer-use"
    [ -f "$dir/SKILL.md" ] &&
        [ -f "$dir/.gnome-wayland-computer-use-managed" ]
}

check_is_desktop_capture_extension_ready() {
    gdbus introspect --session \
        --dest io.github.ryanraposo.GnomeWaylandDesktopCapture \
        --object-path /io/github/ryanraposo/GnomeWaylandDesktopCapture \
        2>/dev/null |
        grep -q "interface io.github.ryanraposo.GnomeWaylandDesktopCapture"
}

# ── Check functions (print result, return 0/1) ──

check_session() {
    local s
    s=$(check_get_session)
    if [ "$s" = "wayland" ]; then
        check_ok "Session: Wayland"; check_pass; return 0
    else
        check_fail "Session: $s (expected wayland)"; check_xfail; return 1
    fi
}

check_desktop() {
    local d
    d=$(check_get_desktop)
    if [[ "$d" == *"GNOME"* ]]; then
        check_ok "Desktop: $d"; check_pass; return 0
    else
        check_fail "Desktop: $d (expected GNOME)"; check_xfail; return 1
    fi
}

check_gnome_shell() {
    if check_is_gnome_shell_running; then
        check_ok "GNOME Shell running"; check_pass; return 0
    else
        check_fail "GNOME Shell not running"; check_xfail; return 1
    fi
}

check_xwayland() {
    if check_is_xwayland_running; then
        check_ok "XWayland running"; check_pass; return 0
    else
        check_info "XWayland not running (expected on pure Wayland)"; check_xfail; return 1
    fi
}

check_toolkit_accessibility() {
    if check_is_toolkit_accessibility_enabled; then
        check_ok "toolkit-accessibility enabled"; check_pass; return 0
    else
        check_fail "toolkit-accessibility disabled (run: gsettings set ... toolkit-accessibility true)"; check_xfail; return 1
    fi
}

check_atspi_bus() {
    if check_is_atspi_bus_alive; then
        check_ok "AT-SPI2 D-Bus alive (org.a11y.Bus)"; check_pass; return 0
    else
        check_fail "AT-SPI2 D-Bus not reachable"; check_xfail; return 1
    fi
}

check_atspi_socket() {
    if check_is_atspi_socket_exists; then
        check_ok "AT-SPI2 socket at $(check_get_atspi_socket)"; check_pass; return 0
    else
        check_fail "AT-SPI2 socket missing"; check_xfail; return 1
    fi
}

check_skill() {
    if check_skill_installed; then
        check_ok "Agent skill installed"; check_pass; return 0
    else
        check_fail "Agent skill not installed"; check_xfail; return 1
    fi
}

check_hermes_skill() {
    if check_hermes_skill_installed; then
        check_ok "Hermes skill installed"; check_pass; return 0
    else
        check_info "Hermes skill not installed (Hermes not detected)"; check_xfail; return 1
    fi
}

check_desktop_capture_extension() {
    if check_is_desktop_capture_extension_ready; then
        check_ok "Focus-free desktop-layer capture ready"
        check_pass
        return 0
    else
        check_fail "Desktop capture extension not loaded (sign out of the GNOME session and sign back in once)"
        check_xfail
        return 1
    fi
}

check_uinput() {
    if check_has_uinput_device; then
        check_ok "/dev/uinput present"; check_pass; return 0
    else
        check_fail "/dev/uinput not found"; check_xfail; return 1
    fi
}

check_input_group() {
    if check_is_input_group_member; then
        check_ok "User in 'input' group"; check_pass; return 0
    else
        check_fail "User not in 'input' group (run: sudo usermod -aG input $USER)"; check_xfail; return 1
    fi
}

check_ydotoold() {
    if ! check_is_ydotoold_installed; then
        check_info "ydotoold not installed (PX Rung fallback degraded)"; check_xfail; return 1
    fi
    local ok=0
    if check_is_ydotoold_enabled; then check_ok "ydotoold.service enabled"; ((ok++)) || true
    else check_fail "ydotoold.service not enabled"; fi
    if check_is_ydotoold_running; then
        check_ok "ydotoold.service running"; ((ok++)) || true
    elif check_is_ydotoold_process_up; then
        check_info "ydotoold process running (outside systemd)"; ((ok++)) || true
    else
        check_fail "ydotoold.service not running"
    fi
    if [ "$ok" -eq 2 ]; then check_pass; else check_xfail; fi
    return $((2 - ok))
}

check_cua_driver() {
    if ! check_is_cua_driver_installed; then
        check_fail "cua-driver not installed (run: hermes computer-use install)"
        check_xfail
        return 1
    fi
    if check_is_cua_driver_running; then
        check_ok "Hermes computer_use backend running"
        check_pass
        return 0
    fi
    check_fail "Hermes computer_use backend not ready"
    check_xfail
    return 1
}
