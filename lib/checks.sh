#!/usr/bin/env bash
# lib/checks.sh — shared validation library for gnome-wayland-computer-use

CK_R='\033[0;31m'; CK_G='\033[0;32m'; CK_Y='\033[1;33m'; CK_N='\033[0m'
check_ok()   { printf "  ${CK_G}✓${CK_N} %s\n" "$*"; }
check_fail() { printf "  ${CK_R}✗${CK_N} %s\n" "$*"; }
check_info() { printf "  ${CK_Y}→${CK_N} %s\n" "$*"; }
check_hr()   { echo "────────────────────────────────────────"; }

CK_SCORE=0; CK_TOTAL=0
check_pass()  { ((CK_SCORE++)) || true; ((CK_TOTAL++)) || true; }
check_xfail() { ((CK_TOTAL++)) || true; }

check_version_ge() {
    [ $# -eq 2 ] || return 2
    [ -n "$1" ] || return 2
    [ -n "$2" ] || return 1
    printf '%s\n%s\n' "$2" "$1" | sort -V | head -1 | grep -qF "$2"
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

check_is_wayland() { [ "$(check_get_session)" = wayland ]; }
check_is_gnome() { [[ "$(check_get_desktop)" == *GNOME* ]]; }
check_is_gnome_shell_running() { pgrep -x gnome-shell &>/dev/null; }
check_is_xwayland_running() { pgrep -x Xwayland &>/dev/null; }

check_is_toolkit_accessibility_enabled() {
    [ "$(gsettings get org.gnome.desktop.interface toolkit-accessibility 2>/dev/null || true)" = true ]
}
check_is_atspi_bus_alive() {
    gdbus introspect --session --dest org.a11y.Bus --object-path /org/a11y/bus 2>/dev/null | grep -q 'interface org.a11y.Bus'
}
check_get_atspi_socket() {
    printf '%s\n' "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/at-spi/bus"
}
check_is_atspi_socket_exists() { [ -S "$(check_get_atspi_socket)" ]; }
check_start_atspi_service() {
    systemctl --user start at-spi-bus-launcher.service 2>/dev/null || {
        /usr/libexec/at-spi-bus-launcher --launch-immediately 2>/dev/null &
        disown
    }
    for _ in 1 2 3; do check_is_atspi_socket_exists && return 0; sleep 1; done
    return 1
}

check_has_uinput_device() { [ -c /dev/uinput ]; }
check_is_input_group_member() { id -nG 2>/dev/null | tr ' ' '\n' | grep -qx input; }
check_is_ydotoold_installed() { command -v ydotoold &>/dev/null; }
check_is_ydotoold_enabled() {
    systemctl --user is-enabled ydotool.service &>/dev/null || systemctl --user is-enabled ydotoold.service &>/dev/null
}
check_is_ydotoold_running() {
    systemctl --user is-active ydotool.service &>/dev/null || systemctl --user is-active ydotoold.service &>/dev/null
}
check_is_ydotoold_process_up() { pgrep -x ydotoold &>/dev/null; }
check_is_cua_driver_installed() { command -v cua-driver &>/dev/null; }
check_is_cua_driver_running() {
    systemctl --user is-active gnome-wayland-computer-use.service &>/dev/null && timeout 3 cua-driver status &>/dev/null
}

check_skill_installed() {
    [ -f "$HOME/.agents/skills/gnome-wayland-computer-use/SKILL.md" ]
}
check_is_hermes_integration_enabled() {
    [ -f "$HOME/.agents/skills/gnome-wayland-computer-use/.hermes-integration" ]
}
check_hermes_skill_installed() {
    local dir="${HERMES_HOME:-$HOME/.hermes}/skills/computer-use"
    [ -f "$dir/SKILL.md" ] && [ -f "$dir/.gnome-wayland-computer-use-managed" ]
}

check_portal_interface() {
    local interface="$1"
    gdbus introspect --session --dest org.freedesktop.portal.Desktop \
        --object-path /org/freedesktop/portal/desktop 2>/dev/null |
        grep -q "interface org.freedesktop.portal.${interface}"
}
check_is_screencast_portal_ready() { check_portal_interface ScreenCast; }
check_is_screenshot_portal_ready() { check_portal_interface Screenshot; }
check_is_pipewire_core_ready() {
    command -v pw-cli &>/dev/null && pw-cli info 0 &>/dev/null
}
check_is_wireplumber_ready() {
    systemctl --user is-active wireplumber.service &>/dev/null || pgrep -x wireplumber &>/dev/null
}
check_is_pipewire_capture_ready() {
    local python="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
    [ -x "$python" ] || python="$(command -v python3 2>/dev/null || true)"
    [ -n "$python" ] || return 1
    "$python" -c "import gi; gi.require_version('Gst','1.0'); from gi.repository import Gst" 2>/dev/null || return 1
    command -v gst-inspect-1.0 &>/dev/null || return 1
    gst-inspect-1.0 pipewiresrc &>/dev/null && gst-inspect-1.0 pngenc &>/dev/null
}
check_has_screencast_restore_token() {
    [ -s "${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use/screencast-restore-token" ]
}
check_legacy_capture_extension_absent() {
    [ ! -d "$HOME/.local/share/gnome-shell/extensions/desktop-capture@gnome-wayland-computer-use" ]
}

check_winrects_dir() {
    printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/winrects@cua"
}
check_cua_helper_installer() {
    printf '%s\n' "${CUA_DRIVER_HOME:-$HOME/.cua-driver}/packages/current/wayland-helper/install.sh"
}
check_is_cua_winrects_installed() { [ -f "$(check_winrects_dir)/extension.js" ] && [ -f "$(check_winrects_dir)/metadata.json" ]; }
check_is_cua_helper_packaged() { [ -x "$(check_cua_helper_installer)" ]; }
check_is_cua_winrects_active() {
    command -v gnome-extensions &>/dev/null || return 1
    gnome-extensions info winrects@cua 2>/dev/null | grep -q 'State:[[:space:]]*ACTIVE'
}
check_has_cua_winrects_owner_marker() {
    [ -f "${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use/cua-winrects-managed" ]
}
check_get_winrects_bus_owner_pid() {
    local owner pid
    owner=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetNameOwner org.cua.WinRects 2>/dev/null | sed -n "s/.*'\([^']*\)'.*/\1/p")
    [ -n "$owner" ] || return 1
    pid=$(gdbus call --session --dest org.freedesktop.DBus --object-path /org/freedesktop/DBus \
        --method org.freedesktop.DBus.GetConnectionUnixProcessID "$owner" 2>/dev/null | grep -oE '[0-9]+' | head -1)
    [ -n "$pid" ] || return 1
    printf '%s\n' "$pid"
}
check_is_winrects_served_by_gnome_shell() {
    local pid exe
    pid=$(check_get_winrects_bus_owner_pid) || return 1
    exe=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
    [ "$(basename "$exe")" = gnome-shell ]
}

check_session() {
    local s; s=$(check_get_session)
    if [ "$s" = wayland ]; then check_ok "Session: Wayland"; check_pass; return 0; fi
    check_fail "Session: $s (expected wayland)"; check_xfail; return 1
}
check_desktop() {
    local d; d=$(check_get_desktop)
    if [[ "$d" == *GNOME* ]]; then check_ok "Desktop: $d"; check_pass; return 0; fi
    check_fail "Desktop: $d (expected GNOME)"; check_xfail; return 1
}
check_gnome_shell() {
    if check_is_gnome_shell_running; then check_ok "GNOME Shell running"; check_pass; return 0; fi
    check_fail "GNOME Shell not running"; check_xfail; return 1
}
check_xwayland() {
    if check_is_xwayland_running; then check_ok "XWayland running"; check_pass; return 0; fi
    check_info "XWayland not running (fine on pure Wayland)"; check_pass; return 0
}
check_toolkit_accessibility() {
    if check_is_toolkit_accessibility_enabled; then check_ok "toolkit-accessibility enabled"; check_pass; return 0; fi
    check_fail "toolkit-accessibility disabled"; check_xfail; return 1
}
check_atspi_bus() {
    if check_is_atspi_bus_alive; then check_ok "AT-SPI2 D-Bus alive"; check_pass; return 0; fi
    check_fail "AT-SPI2 D-Bus not reachable"; check_xfail; return 1
}
check_atspi_socket() {
    if check_is_atspi_socket_exists; then check_ok "AT-SPI2 socket ready"; check_pass; return 0; fi
    check_fail "AT-SPI2 socket missing"; check_xfail; return 1
}
check_skill() {
    if check_skill_installed; then check_ok "Agent skill installed"; check_pass; return 0; fi
    check_fail "Agent skill not installed"; check_xfail; return 1
}
check_hermes_skill() {
    if ! check_is_hermes_integration_enabled; then check_info "Hermes integration not selected"; check_pass; return 0; fi
    if check_hermes_skill_installed; then check_ok "Hermes skill installed"; check_pass; return 0; fi
    check_fail "Hermes integration selected but skill missing"; check_xfail; return 1
}
check_screencast_portal() {
    if check_is_screencast_portal_ready; then check_ok "XDG ScreenCast portal ready"; check_pass; return 0; fi
    check_fail "XDG ScreenCast portal not reachable"; check_xfail; return 1
}
check_screenshot_portal() {
    if check_is_screenshot_portal_ready; then check_ok "XDG Screenshot portal ready"; check_pass; return 0; fi
    check_fail "XDG Screenshot portal not reachable"; check_xfail; return 1
}
check_pipewire_core() {
    if check_is_pipewire_core_ready; then check_ok "PipeWire core responding"; check_pass; return 0; fi
    check_fail "PipeWire core not responding"; check_xfail; return 1
}
check_wireplumber() {
    if check_is_wireplumber_ready; then check_ok "WirePlumber session manager active"; check_pass; return 0; fi
    check_fail "WirePlumber not active"; check_xfail; return 1
}
check_pipewire_capture() {
    if check_is_pipewire_capture_ready; then check_ok "GStreamer PipeWire capture ready"; check_pass; return 0; fi
    check_fail "GStreamer PipeWire capture stack incomplete"; check_xfail; return 1
}
check_restore_token() {
    if check_has_screencast_restore_token; then check_ok "ScreenCast restore token cached"; check_pass; return 0; fi
    check_info "No ScreenCast restore token yet (first capture may ask for monitor permission)"; check_pass; return 0
}
check_legacy_capture_extension() {
    if check_legacy_capture_extension_absent; then check_ok "Obsolete project capture extension removed"; check_pass; return 0; fi
    check_fail "Obsolete project capture extension still installed; rerun installer"; check_xfail; return 1
}
check_uinput() {
    if check_has_uinput_device; then check_ok "/dev/uinput present"; check_pass; return 0; fi
    check_fail "/dev/uinput not found"; check_xfail; return 1
}
check_input_group() {
    if check_is_input_group_member; then check_ok "User in input group"; check_pass; return 0; fi
    check_fail "User not in input group"; check_xfail; return 1
}
check_ydotoold() {
    if ! check_is_ydotoold_installed; then check_info "ydotoold not installed (last-resort input degraded)"; check_xfail; return 1; fi
    if check_is_ydotoold_running || check_is_ydotoold_process_up; then check_ok "ydotoold running"; check_pass; return 0; fi
    check_fail "ydotoold not running"; check_xfail; return 1
}
check_cua_driver() {
    if ! check_is_hermes_integration_enabled; then check_info "Hermes/Cua profile not selected"; check_pass; return 0; fi
    if check_is_cua_driver_running; then check_ok "Hermes computer_use backend running"; check_pass; return 0; fi
    check_fail "Hermes computer_use backend not ready"; check_xfail; return 1
}
check_cua_helper_package() {
    if ! check_is_hermes_integration_enabled; then check_info "Cua GNOME precision not selected"; check_pass; return 0; fi
    if check_is_cua_helper_packaged; then check_ok "Cua package contains wayland-helper/install.sh"; check_pass; return 0; fi
    check_fail "Cua package does not contain the documented Wayland helper installer"; check_xfail; return 1
}
check_cua_winrects_installed() {
    if ! check_is_hermes_integration_enabled; then check_info "Cua WinRects not selected"; check_pass; return 0; fi
    if check_is_cua_winrects_installed; then check_ok "Cua WinRects installed"; check_pass; return 0; fi
    check_fail "Cua WinRects not installed"; check_xfail; return 1
}
check_cua_winrects_active() {
    if ! check_is_hermes_integration_enabled; then check_info "Cua WinRects not selected"; check_pass; return 0; fi
    if check_is_cua_winrects_active; then check_ok "winrects@cua ACTIVE"; check_pass; return 0; fi
    if check_is_cua_winrects_installed; then
        check_info "winrects@cua installed but not ACTIVE — GNOME session reload required"
        check_xfail
        return 1
    fi
    check_fail "winrects@cua unavailable"; check_xfail; return 1
}
check_cua_winrects_bus() {
    if ! check_is_hermes_integration_enabled; then check_info "Cua WinRects bus not selected"; check_pass; return 0; fi
    if check_is_winrects_served_by_gnome_shell; then check_ok "org.cua.WinRects served by GNOME Shell"; check_pass; return 0; fi
    if check_is_cua_winrects_installed && ! check_is_cua_winrects_active; then
        check_info "org.cua.WinRects pending GNOME session reload"; check_xfail; return 1
    fi
    check_fail "org.cua.WinRects is not owned by GNOME Shell"; check_xfail; return 1
}
