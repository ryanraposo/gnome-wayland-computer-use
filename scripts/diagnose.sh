#!/usr/bin/env bash
# diagnose.sh — full-stack diagnostic for gnome-wayland-computer-use
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
. "$SCRIPT_DIR/lib/checks.sh"

JSON=false
for arg in "$@"; do
    [ "$arg" = "--json" ] && JSON=true
done

check_and_report() {
    local name="$1" detail="${2:-}"; shift 2
    local rc=0
    if $JSON; then
        "$@" > /dev/null 2>&1 || rc=$?
        printf '{"check":"%s","pass":%s,"detail":"%s"}\n' \
            "$name" "$([ "$rc" -eq 0 ] && echo true || echo false)" "$detail"
    else
        "$@" || rc=$?
    fi
    return "$rc"
}

if ! $JSON; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  gnome-wayland-computer-use diagnose"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

# ── 1. Display server ──────────────────────────────────────────────────
$JSON || { check_hr; echo "── 1. Display server"; }
check_and_report session "$(check_get_session)" check_session
check_and_report desktop "$(check_get_desktop)" check_desktop
check_and_report gnome_shell "" check_gnome_shell
check_and_report xwayland "" check_xwayland

# ── 2. Accessibility ───────────────────────────────────────────────────
$JSON || { echo ""; check_hr; echo "── 2. Accessibility"; }
check_and_report toolkit_accessibility "" check_toolkit_accessibility
check_and_report atspi_bus "" check_atspi_bus
check_and_report atspi_socket "" check_atspi_socket

# ── 3. Skill ───────────────────────────────────────────────────────────
$JSON || { echo ""; check_hr; echo "── 3. Skill"; }
check_and_report skill "" check_skill
check_and_report hermes_skill "" check_hermes_skill

# ── 4. Input Permissions ───────────────────────────────────────────────
$JSON || { echo ""; check_hr; echo "── 4. Input"; }
check_and_report uinput "" check_uinput
check_and_report input_group "" check_input_group
check_and_report ydotoold "" check_ydotoold

# ── Summary ────────────────────────────────────────────────────────────
if ! $JSON; then
    check_print_summary
    echo ""
fi
if $JSON; then
    printf '{"check":"summary","pass":true,"detail":"%d/%d"}\n' "$CK_SCORE" "$CK_TOTAL"
fi
