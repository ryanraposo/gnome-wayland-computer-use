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
    'Core rule' 'Call budget' 'Execution ladder' 'Known target' \
    'WORLDLINE postconditions' 'Whole screen' '.gwcu: durable truth, not runtime state' \
    'Failure and refusal policy' 'Completion proof'
do
    grep -Fqi "## $heading" "$ROOT/SKILL.md" || fail "skill lost: $heading"
done
grep -q 'MUST cross the model/tool boundary exactly once' "$ROOT/SKILL.md" || fail "one-call invariant softened"
grep -q 'computer-use.sh" span --actions-json' "$ROOT/SKILL.md" || fail "span surface missing"
grep -q 'worldline-capture.sh' "$ROOT/SKILL.md" || fail "WORLDLINE surface missing"
grep -q 'Never answer a Cua refusal with raw pointer/keyboard injection' "$ROOT/SKILL.md" || fail "refusal boundary missing"
grep -q 'No X11 or XWayland session is required' "$ROOT/SKILL.md" || fail "GNOME Wayland contract missing"
pass "skill teaches Cua + WORLDLINE execution"

grep -q '^## Maintaining this repository$' "$ROOT/AGENTS.md" || fail "repository guide lost maintenance routing"
grep -q 'Persistent machine/user truth never belongs in AGENTS.md' "$ROOT/AGENTS.md" || fail "AGENTS permits machine truth"
test -f "$ROOT/references/skill-ux-contract.md" || fail "skill UX contract missing"
grep -q 'references/skill-ux-contract.md' "$ROOT/install.sh" || fail "installer does not ship skill UX contract"
pass "repository/runtime authority remains separated"

version=$(tr -d '[:space:]' <"$ROOT/VERSION")
grep -q "^version: ${version}$" "$ROOT/SKILL.md" || fail "skill version mismatch"
[ "$version" = 2.3.0 ] || fail "release version is 2.3.0"
pass "version identity is consistent"
