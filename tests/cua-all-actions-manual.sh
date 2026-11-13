#!/usr/bin/env bash
# tests/cua-all-actions-manual.sh — manual end-to-end runbook for every Cua
# foreground action through the Hermes tools.override plugin on a live
# Ubuntu 26.04 GNOME Wayland desktop.
#
# Prerequisites: a live GNOME Wayland session, GWCU installed (READY // PROVED),
# Hermes running with the gnome-wayland-computer-use skill + policy plugin
# enabled, and a launchable local test application (TEST_APP, default
# gnome-text-editor).
#
# Each Cua foreground action is sent through the installed span runner
# (computer-use.sh span), which proves exact (pid, window_id) presentation
# before forwarding foreground delivery_mode input to Cua — the same gate the
# Hermes tools.override plugin enforces. Expected: every action prints ok:true
# and the final target is left focused + visible on screen.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMPUTER_USE="$ROOT/scripts/computer-use.sh"
PRESENTER="$ROOT/scripts/present-window.py"
PYTHON="${PYTHON:-python3}"
TEST_APP="${TEST_APP:-gnome-text-editor}"

PASS=0
FAIL=0

note() { printf '[runbook] %s\n' "$*"; }
ok()   { PASS=$((PASS + 1)); note "ok - $*"; }
bad()  { FAIL=$((FAIL + 1)); note "FAIL - $*"; }

json_get() { printf '%s' "$1" | "$PYTHON" -c "import json,sys; print(json.load(sys.stdin)$2)"; }

# 1. Confirm Wayland.
if [ "${XDG_SESSION_TYPE:-}" != "wayland" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
    bad "not a Wayland session (XDG_SESSION_TYPE=${XDG_SESSION_TYPE:-<unset>} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>})"
    exit 1
fi
ok "Wayland session (XDG_SESSION_TYPE=${XDG_SESSION_TYPE} WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-<unset>})"

# 2. ACQUIRE a test app through Cua launch_app and bind its exact (pid, window_id).
note "ACQUIRE $TEST_APP via Cua launch_app"
ACQUIRE_JSON="$("$COMPUTER_USE" span --actions-json "$(cat <<JSON
{
  \"schema\":\"gwcu.action-span.request.v1\",
  \"control\":{\"visible_required\":true,\"explicit_mode\":\"foreground\"},
  \"actions\":[{\"name\":\"launch_app\",\"arguments\":{\"app\":\"$TEST_APP\"}}]
}
JSON
)" )" || { bad "launch_app span for $TEST_APP"; exit 1; }
ACQUIRE_OK="$(json_get "$ACQUIRE_JSON" "['results'][0]['result'].get('ok')")"
if [ "$ACQUIRE_OK" != "True" ]; then
    bad "launch_app did not return ok:true ($ACQUIRE_JSON)"
    exit 1
fi
ok "launch_app acquired $TEST_APP"
PID="$(json_get "$ACQUIRE_JSON" "['results'][0]['result'].get('target',{}).get('pid','')")"
WINDOW_ID="$(json_get "$ACQUIRE_JSON" "['results'][0]['result'].get('target',{}).get('window_id','')")"
note "bound target pid=$PID window_id=$WINDOW_ID"

# 3. PRESENT the exact target through Cua's attested GNOME helper.
note "PRESENT pid=$PID window_id=$WINDOW_ID"
PRESENT_JSON="$("$PYTHON" "$PRESENTER" present --pid "$PID" --window-id "$WINDOW_ID")"
PRESENT_OK="$(json_get "$PRESENT_JSON" "['ok']")"
if [ "$PRESENT_OK" != "True" ]; then
    bad "presentation not proved ($PRESENT_JSON)"
    exit 1
fi
ok "present pid=$PID window_id=$WINDOW_ID ok:true"

# 4. Exercise every Cua foreground action through the foreground gate.
#    Coordinate-dependent actions target (100,100); on a live desktop the
#    element under that coordinate receives the input. type/key/set_value
#    act on the focused field of the acquired window.
declare -A ARGS=(
  [click]='{"x":100,"y":100}'
  [double_click]='{"x":100,"y":100}'
  [right_click]='{"x":100,"y":100}'
  [middle_click]='{"x":100,"y":100}'
  [drag]='{"x":100,"y":100,"to_x":150,"to_y":150}'
  [scroll]='{"x":100,"y":100,"amount":5}'
  [type]='{"text":"gwcu-runbook"}'
  [key]='{"key":"Return"}'
  [set_value]='{"value":"gwcu"}'
)
for action in click double_click right_click middle_click drag scroll type key set_value; do
    note "$action pid=$PID window_id=$WINDOW_ID"
    ACTION_JSON="$(cat <<JSON
{
  \"schema\":\"gwcu.action-span.request.v1\",
  \"control\":{\"visible_required\":true,\"explicit_mode\":\"foreground\"},
  \"actions\":[{\"name\":\"$action\",\"arguments\":{\"pid\":$PID,\"window_id\":$WINDOW_ID${ARGS[$action]:+, }${ARGS[$action]:-}}]}
JSON
)"
    # Strip a trailing ", " when ARGS is empty (none here; all entries have args).
    RESULT_JSON="$("$COMPUTER_USE" span --actions-json "$ACTION_JSON")" || { bad "span runner errored for $action"; continue; }
    ACTION_OK="$(json_get "$RESULT_JSON" "['results'][0]['result'].get('ok')")"
    if [ "$ACTION_OK" = "True" ]; then
        ok "$action pid=$PID window_id=$WINDOW_ID ok:true"
    else
        bad "$action pid=$PID window_id=$WINDOW_ID ($RESULT_JSON)"
    fi
done

# 5. Re-validate identity and present the final exact target visibly.
note "FINAL PRESENT pid=$PID window_id=$WINDOW_ID"
FINAL_JSON="$("$PYTHON" "$PRESENTER" present --pid "$PID" --window-id "$WINDOW_ID")"
FINAL_OK="$(json_get "$FINAL_JSON" "['ok']")"
if [ "$FINAL_OK" != "True" ]; then
    bad "final presentation not proved ($FINAL_JSON)"
    exit 1
fi
ok "final present pid=$PID window_id=$WINDOW_ID ok:true"

note "summary: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
