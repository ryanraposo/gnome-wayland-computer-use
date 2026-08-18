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
    'Invocation contract' 'Core rule' 'Control priority' 'Call budget' 'Execution ladder' 'Known target' \
    'WORLDLINE postconditions' 'Whole screen' '`.gwcu`: durable truth, not runtime state' \
    'Failure and refusal policy' 'Completion proof'
do
    grep -Fqi "## $heading" "$ROOT/SKILL.md" || fail "skill lost: $heading"
done
grep -Fq '/computer-use <task>' "$ROOT/SKILL.md" || fail "task-form slash invocation missing"
grep -Fq 'Everything else is a task.' "$ROOT/SKILL.md" || fail "task/subcommand dispatch rule missing"
grep -Fq 'status`, `background`, `managed`, `truths`, `consent`, `doctor`, and `help' "$ROOT/SKILL.md" || fail "reserved subcommand set drifted"
if grep -Fq 'ctx.register_command(' "$ROOT/runtimes/hermes/__init__.py"; then
    fail "Hermes plugin shadows the native computer-use skill command"
fi
grep -Fq 'installed skill owns it' "$ROOT/runtimes/hermes/__init__.py" || fail "Hermes compatibility shim contract missing"
pass "/computer-use accepts both tasks and reserved subcommands"

grep -q 'MUST cross the model/tool boundary exactly once' "$ROOT/SKILL.md" || fail "one-call invariant softened"
grep -q 'computer-use.sh" span --actions-json' "$ROOT/SKILL.md" || fail "span surface missing"
grep -q 'worldline-capture.sh' "$ROOT/SKILL.md" || fail "WORLDLINE surface missing"
grep -q 'Never answer a Cua refusal with raw pointer/keyboard injection' "$ROOT/SKILL.md" || fail "refusal boundary missing"
grep -q 'No X11 or XWayland session is required' "$ROOT/SKILL.md" || fail "GNOME Wayland contract missing"
grep -q 'toggles priority for background computer use' "$ROOT/SKILL.md" || fail "background command contract missing"
pass "skill teaches Cua + WORLDLINE execution"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SURFACE="$ROOT/scripts/computer-use.sh"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background status >"$TMP/default"
grep -q 'Background computer use: OFF' "$TMP/default" || fail "background default is not obvious control"
grep -q 'FASTEST / most deterministic' "$TMP/default" || fail "performance recommendation missing"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background >"$TMP/on"
grep -q 'Background computer use: ON' "$TMP/on" || fail "bare background command did not toggle on"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background >"$TMP/off"
grep -q 'Background computer use: OFF' "$TMP/off" || fail "bare background command did not toggle off"
grep -q 'Prioritize background computer use when available? Obvious control is faster and more deterministic' "$ROOT/install.sh" || fail "installer background choice missing"
pass "background priority is deterministic, toggled, and installer-visible"

grep -q '^## Maintaining this repository$' "$ROOT/AGENTS.md" || fail "repository guide lost maintenance routing"
grep -q 'Persistent machine/user truth never belongs in AGENTS.md' "$ROOT/AGENTS.md" || fail "AGENTS permits machine truth"
test -f "$ROOT/references/skill-ux-contract.md" || fail "skill UX contract missing"
grep -q 'references/skill-ux-contract.md' "$ROOT/install.sh" || fail "installer does not ship skill UX contract"
pass "repository/runtime authority remains separated"

version=$(tr -d '[:space:]' <"$ROOT/VERSION")
grep -q "^version: ${version}$" "$ROOT/SKILL.md" || fail "skill version mismatch"
[ "$version" = 2.3.0 ] || fail "release version is 2.3.0"
pass "version identity is consistent"
