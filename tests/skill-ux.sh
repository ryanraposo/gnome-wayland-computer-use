#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    printf 'not ok - %s\n' "$1" >&2
    exit 1
}

pass() {
    printf 'ok - %s\n' "$1"
}

skill_description() {
    awk '
        NR == 1 && $0 == "---" { frontmatter = 1; next }
        frontmatter && $0 == "---" { exit }
        frontmatter && /^description:[[:space:]]*/ {
            sub(/^description:[[:space:]]*/, "")
            print
            exit
        }
    ' "$1"
}

hermes_description=$(skill_description "$ROOT/SKILL.md")
portable_description=$(skill_description "$ROOT/runtimes/openai/SKILL.md")

[ -n "$hermes_description" ] || fail "Hermes skill has a description"
[ -n "$portable_description" ] || fail "portable skill has a description"
[ "${#hermes_description}" -lt 60 ] || \
    fail "Hermes skill description is below 60 characters"
[ "${#portable_description}" -lt 60 ] || \
    fail "portable skill description is below 60 characters"
[ "$hermes_description" = "$portable_description" ] || \
    fail "runtime descriptions stay identical"
pass "runtime descriptions are identical and below 60 characters"

grep -q '^## Workflow Contract$' "$ROOT/SKILL.md" || \
    fail "Hermes skill owns the workflow"
grep -q '^## Execution State Machine$' "$ROOT/SKILL.md" || \
    fail "Hermes skill declares its state machine"
grep -q '^## Workflow Contract$' "$ROOT/runtimes/openai/SKILL.md" || \
    fail "portable skill owns the workflow"
pass "both runtime payloads own execution"

grep -q '^## Maintaining this repository$' "$ROOT/AGENTS.md" || \
    fail "repository guide owns maintenance routing"
grep -q 'Keep `AGENTS.md` repository-facing and `SKILL.md` invocation-facing' \
    "$ROOT/AGENTS.md" || fail "repository and runtime authority stay distinct"
pass "repository guidance stays repository-facing"

test -f "$ROOT/references/skill-ux-contract.md" || \
    fail "skill UX contract exists"
grep -q '^## Phase transitions$' "$ROOT/references/skill-ux-contract.md" || \
    fail "skill UX contract defines phase transitions"
grep -q '"references/skill-ux-contract.md"' "$ROOT/install.sh" || \
    fail "installer ships the skill UX contract"
pass "skill UX contract is defined and delivered"

version=$(tr -d '[:space:]' < "$ROOT/VERSION")
grep -q "^version: ${version}$" "$ROOT/SKILL.md" || \
    fail "Hermes version matches VERSION"
pass "version identity is consistent"
