#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

fail() { printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass() { printf 'ok - %s\n' "$1"; }

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
[ "${#hermes_description}" -lt 60 ] || fail "Hermes skill description is below 60 characters"
[ "${#portable_description}" -lt 60 ] || fail "portable skill description is below 60 characters"
[ "$hermes_description" = "$portable_description" ] || fail "runtime descriptions stay identical"
pass "runtime descriptions are identical and below 60 characters"

for heading in 'Workflow contract' 'Execution state machine' 'Latency-first interaction' 'Pixel-only surfaces'; do
    grep -qi "^## ${heading}$" "$ROOT/SKILL.md" || fail "Hermes skill lost: $heading"
done
for heading in 'Workflow contract' 'Latency-first interaction' 'Pixel-only surfaces'; do
    grep -qi "^## ${heading}$" "$ROOT/runtimes/openai/SKILL.md" || fail "portable skill lost: $heading"
done
pass "both runtime payloads own execution, latency, and pixel-only recovery"

grep -q '^## Maintaining this repository$' "$ROOT/AGENTS.md" || fail "repository guide owns maintenance routing"
grep -q 'Keep `AGENTS.md` repository-facing and `SKILL.md` invocation-facing' "$ROOT/AGENTS.md" || \
    fail "repository and runtime authority stay distinct"
grep -q 'end-to-end latency budget' "$ROOT/AGENTS.md" || fail "repository maintenance protects full workflow latency"
grep -q 'Persistent machine/user truth never belongs in AGENTS.md' "$ROOT/AGENTS.md" || fail "repository guidance allows machine truth in prompt prose"
pass "repository guidance stays repository-facing"

test -f "$ROOT/references/skill-ux-contract.md" || fail "skill UX contract exists"
grep -q '^## Phase transitions$' "$ROOT/references/skill-ux-contract.md" || fail "skill UX contract defines phase transitions"
grep -q '^## Latency budget and decision boundaries$' "$ROOT/references/skill-ux-contract.md" || fail "skill UX contract defines decision-boundary latency"
grep -q 'references/skill-ux-contract.md' "$ROOT/install.sh" || fail "installer ships the skill UX contract"
pass "skill UX contract is defined and delivered"

version=$(tr -d '[:space:]' < "$ROOT/VERSION")
grep -q "^version: ${version}$" "$ROOT/SKILL.md" || fail "Hermes version matches VERSION"
[ "$version" = 2.3.0 ] || fail "release version is 2.3.0"
pass "version identity is consistent"
