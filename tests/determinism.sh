#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

for f in SKILL.md runtimes/openai/SKILL.md README.md; do
    grep -qi 'Cua' "$ROOT/$f" || fail "$f lost Cua authority"
    grep -qi 'WORLDLINE' "$ROOT/$f" || fail "$f lost WORLDLINE architecture"
done
pass "runtime and README surfaces agree on authority"

for f in SKILL.md runtimes/openai/SKILL.md README.md; do
    grep -qi 'No X11' "$ROOT/$f" || fail "$f lost GNOME Wayland qualification"
    grep -qi 'Remote Desktop' "$ROOT/$f" || fail "$f lost local portal consent"
done
pass "GNOME Wayland authority contract is aligned"

grep -qi 'Observation is an interrupt' "$ROOT/README.md" || fail "README lost WORLDLINE inversion"
grep -qi 'valid until invalidated' "$ROOT/README.md" || fail "README lost invalidation rule"
grep -qi 'postcondition' "$ROOT/README.md" || fail "README lost predicate rule"
grep -qi 'WORLDLINE is transient' "$ROOT/README.md" || fail "README lost state lifetime boundary"
grep -Fq '0x0' "$ROOT/README.md" || fail "README lost the little guy"
[ "$(grep -Fc 'Agents have variable success using Linux.' "$ROOT/README.md")" -eq 1 ] || fail "README must use the single little-guy-era description exactly once"
! grep -Fq 'Computer use for Ubuntu 26.04 GNOME Wayland that keeps already-known reality out of the model loop.' "$ROOT/README.md" || fail "README still carries the discarded first description"
pass "README carries state lifetimes, little-guy identity and one description"

for retired in WORLDLINE.md GWCU.md DETERMINISM.md CAPABILITIES.md PERF_NOTES.md references/skill-ux-contract.md; do
    [ ! -e "$ROOT/$retired" ] || fail "parallel documentation still exists: $retired"
done
pass "README is the only human-facing project documentation"

site="$ROOT/index.html"
grep -Fq '0x0' "$site" || fail "landing page lost the little guy"
grep -Fq '<h1>gnome-wayland-computer-use</h1>' "$site" || fail "landing page lost original-style title"
[ "$(grep -Fc 'class="description"' "$site")" -eq 1 ] || fail "landing page must contain one primary description element"
[ "$(grep -Fc 'Agents have variable success using Linux.' "$site")" -eq 1 ] || fail "landing page must use the lower original description exactly once"
! grep -Fq 'Computer use that remembers what just happened.' "$site" || fail "landing page still carries the discarded first description"
grep -Fq '/computer-use open YouTube' "$site" || fail "landing page lost task-form slash UX"
grep -Fq 'curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash' "$site" || fail "landing page install command drifted"
grep -Fq 'prefers-reduced-motion' "$site" || fail "landing page lost reduced-motion handling"
grep -Fq 'background:var(--bg)' "$site" || fail "landing page lost dark little-guy visual language"
grep -Fq 'mascot-card' "$site" || fail "landing page lost mascot panel"
for retired in WORLDLINE.md GWCU.md DETERMINISM.md CAPABILITIES.md PERF_NOTES.md; do ! grep -Fq "$retired" "$site" || fail "landing page links retired doc: $retired"; done
pass "little-guy landing page stays current, accessible and README-only"

! grep -Eq 'ydotool|/dev/uinput' "$ROOT/scripts/worldline.py" || fail "WORLDLINE owns input"
! grep -Eq 'ExecStart=.*cua-driver.*serve' "$ROOT/install.sh" || fail "installer creates a Cua daemon"
grep -q 'Cua Driver as the control authority' "$ROOT/SKILL.md" || fail "skill lost single actuator"
grep -q 'Never answer a Cua refusal with raw pointer/keyboard injection' "$ROOT/SKILL.md" || fail "refusal boundary missing"
pass "one control plane remains"

grep -q 'scripts/action-span.py' "$ROOT/install.sh" || fail "installer still omits action span"
grep -q 'scripts/worldline.py' "$ROOT/install.sh" || fail "installer omits WORLDLINE"
grep -q 'gnome-wayland-computer-use-worldline.socket' "$ROOT/install.sh" || fail "installer omits WORLDLINE unit"
grep -q 'gnome-wayland-computer-use-worldline.socket' "$ROOT/scripts/teardown.sh" || fail "teardown omits WORLDLINE unit"
grep -q 'Repo/workspace .gwcu files' "$ROOT/scripts/teardown.sh" || fail "teardown no longer preserves workspace truth"
pass "WORLDLINE lifecycle is installed and reversible"

README_BUDGET_BYTES=8500
size=$(wc -c <"$ROOT/README.md")
[ "$size" -le "$README_BUDGET_BYTES" ] || fail "README exceeds ${README_BUDGET_BYTES}-byte budget (size=$size)"
pass "README stays within ${README_BUDGET_BYTES}-byte budget"
