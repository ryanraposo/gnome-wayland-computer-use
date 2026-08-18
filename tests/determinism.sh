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
pass "README carries state lifetimes and postconditions"

for retired in WORLDLINE.md GWCU.md DETERMINISM.md CAPABILITIES.md PERF_NOTES.md references/skill-ux-contract.md; do
    [ ! -e "$ROOT/$retired" ] || fail "parallel documentation still exists: $retired"
done
pass "README is the only human-facing project documentation"

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
