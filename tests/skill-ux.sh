#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

skill_description() {
    awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f&&/^description:[[:space:]]*/{sub(/^description:[[:space:]]*/,"");print;exit}' "$1"
}

a=$(skill_description "$ROOT/SKILL.md")
b=$(skill_description "$ROOT/runtimes/openai/SKILL.md")
[ -n "$a" ] && [ "${#a}" -lt 60 ] || fail "Hermes description is compact"
[ "$a" = "$b" ] || fail "runtime descriptions differ"
cmp -s "$ROOT/SKILL.md" "$ROOT/runtimes/openai/SKILL.md" || fail "runtime skill payloads drifted"
pass "runtime skills are identical and compact"

for heading in \
    'Invocation contract' 'One actuator, including the browser' 'Core rule' 'Control priority' 'Visible-result contract' \
    'Call budget' 'Execution ladder' 'Known target' 'WORLDLINE postconditions' 'Whole screen' \
    '`.gwcu`: durable truth, not runtime state' 'Failure and refusal policy' 'Completion proof'
do
    grep -Fqi "## $heading" "$ROOT/SKILL.md" || fail "skill lost: $heading"
done
grep -Fq '/computer-use <task>' "$ROOT/SKILL.md" || fail "task-form slash invocation missing"
grep -Fq 'Everything else is a task.' "$ROOT/SKILL.md" || fail "task/subcommand dispatch rule missing"
for sub in status trace present background managed truths consent doctor help; do grep -Fq "/computer-use $sub" "$ROOT/SKILL.md" || fail "reserved subcommand missing: $sub"; done
! grep -Fq 'ctx.register_command(' "$ROOT/runtimes/hermes/__init__.py" || fail "Hermes plugin shadows skill task dispatch"
grep -Fq 'installed skill owns ``/computer-use`` task dispatch' "$ROOT/runtimes/hermes/__init__.py" || fail "Hermes slash ownership contract missing"
grep -Fq 'SUBCOMMANDS["/computer-use"]' "$ROOT/runtimes/hermes/__init__.py" || fail "Hermes completion metadata missing"
grep -Fq 'normalized == "/computer-use"' "$ROOT/runtimes/hermes/__init__.py" || fail "skill-completer exception missing"
pass "/computer-use keeps task dispatch while reserved subcommands autocomplete"

grep -q 'MUST cross the model/tool boundary exactly once' "$ROOT/SKILL.md" || fail "one-call invariant softened"
grep -q 'computer-use.sh" span --actions-json' "$ROOT/SKILL.md" || fail "span surface missing"
grep -q 'worldline-capture.sh' "$ROOT/SKILL.md" || fail "WORLDLINE surface missing"
grep -q 'Never answer a Cua refusal with raw pointer/keyboard injection' "$ROOT/SKILL.md" || fail "refusal boundary missing"
grep -q 'No X11 or XWayland session is required' "$ROOT/SKILL.md" || fail "GNOME Wayland contract missing"
grep -q 'toggles the standing delivery preference' "$ROOT/SKILL.md" || fail "background command contract missing"
grep -q 'documentation lives in `README.md`' "$ROOT/SKILL.md" || fail "skill points at retired docs"
pass "skill teaches one Cua + WORLDLINE execution contract"

# Invisible-control regression constitution.
grep -Fq "do not route browser work through Hermes' separate \`browser_*\` toolset" "$ROOT/SKILL.md" || fail "browser actuator split can recur"
grep -Fq 'cua_browser_state / cua_browser_* actions' "$ROOT/SKILL.md" || fail "Cua browser route is not explicit"
grep -Fq 'binding_quality:"exact"' "$ROOT/SKILL.md" || fail "typed browser route no longer requires exact native binding"
grep -Fq 'mutation_allowed:true' "$ROOT/SKILL.md" || fail "typed browser mutation admission is incomplete"
grep -Fq 'Every mutation invalidates refs.' "$ROOT/SKILL.md" || fail "typed browser refs can silently go stale"
grep -Fq 'An unselected tab may still be fully addressable.' "$ROOT/SKILL.md" || fail "typed browser visibility trap is undocumented"
grep -Fq 'Firefox has no typed page-mutation route' "$ROOT/SKILL.md" || fail "Firefox can be misrouted into typed browser mutation"
grep -Fq 'A hidden/headless/managed browser success is a failure' "$ROOT/SKILL.md" || fail "visible-result failure is not explicit"
grep -Fqi 'There is deliberately **no floating confidence threshold**' "$ROOT/SKILL.md" || fail "confidence arbiter regression guard missing"
! grep -Eq 'F <|F >|0\.40|0\.60|\.40–\.60' "$ROOT/SKILL.md" || fail "obsolete confidence threshold still documented"
grep -Fq 'exact_pid_window -> cua_gnome_present -> focused_visible_proof -> cua_input' "$ROOT/scripts/action-span.py" || fail "action-span lost exact foreground invariant"
grep -Fq 'exact_target_required_for_foreground' "$ROOT/scripts/action-span.py" || fail "targetless foreground can recur"
grep -Fq 'presentation_not_proved' "$ROOT/scripts/action-span.py" || fail "presentation failure can leak into input"
grep -Fq 'tools.override' "$ROOT/runtimes/hermes/plugin.yaml" || fail "Hermes policy override is not declared"
pass "browser and exact foreground presentation are constitutionally covered"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SURFACE="$ROOT/scripts/computer-use.sh"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background status >"$TMP/default"
grep -q 'Background computer use: OFF' "$TMP/default" || fail "background default is not visible takeover"
grep -q 'EXACT VISIBLE TAKEOVER' "$TMP/default" || fail "default takeover contract missing"
XDG_STATE_HOME="$TMP/state" "$SURFACE" trace >"$TMP/trace"
for stage in DISCOVER PRESENT ACT REVALIDATE 'COMPLETE VISIBLY'; do grep -Fq "$stage" "$TMP/trace" || fail "trace lost stage: $stage"; done
grep -Fq 'otherwise STOP before input' "$ROOT/SKILL.md" || fail "pre-actuation failure boundary missing"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background >"$TMP/on"
grep -q 'Background computer use: ON' "$TMP/on" || fail "bare background command did not toggle on"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background >"$TMP/off"
grep -q 'Background computer use: OFF' "$TMP/off" || fail "bare background command did not toggle off"
grep -q 'Default visible takeover is faster and deterministic' "$ROOT/install.sh" || fail "installer background choice missing"
pass "default control path is visible, pre-traced and deterministic"

# New subcommands: list-windows and cursor-color
XDG_STATE_HOME="$TMP/state" "$SURFACE" list-windows >"$TMP/list"
grep -q 'Found [0-9]* windows:' "$TMP/list" || fail "list-windows returned window list"
grep -q '"schema":"gwcu' "$TMP/list" || true  # accepts MCP envelope
XDG_STATE_HOME="$TMP/state" "$SURFACE" list-windows --on-screen-only >"$TMP/list_on"
grep -q 'Found [0-9]* windows:' "$TMP/list_on" || fail "list-windows --on-screen-only works"
XDG_STATE_HOME="$TMP/state" "$SURFACE" cursor-color >"$TMP/cursor"
grep -q 'Set agent cursor color to #00FF00' "$TMP/cursor" || fail "cursor-color default green"
XDG_STATE_HOME="$TMP/state" "$SURFACE" cursor-color "#FF0000" >"$TMP/cursor2"
grep -q 'Set agent cursor color to #FF0000' "$TMP/cursor2" || fail "cursor-color accepts custom hex"
pass "list-windows and cursor-color operator surfaces work"

grep -q '^## Maintaining this repository$' "$ROOT/AGENTS.md" || fail "repository guide lost maintenance routing"
grep -q 'Persistent machine/user truth never belongs in AGENTS.md' "$ROOT/AGENTS.md" || fail "AGENTS permits machine truth"
grep -q 'README.md.*only human-facing documentation file' "$ROOT/AGENTS.md" || fail "repository docs authority is unclear"
pass "repository/runtime/README authority remains separated"

version=$(tr -d '[:space:]' <"$ROOT/VERSION")
grep -q "^version: ${version}$" "$ROOT/SKILL.md" || fail "skill version mismatch"
[ "$version" = 2.3.0 ] || fail "release version is 2.3.0"
pass "version identity is consistent"
