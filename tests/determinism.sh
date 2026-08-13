#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }
skill="$ROOT/SKILL.md"; installer="$ROOT/install.sh"; uninstaller="$ROOT/uninstall.sh"; teardown="$ROOT/scripts/teardown.sh"
diagnose="$ROOT/scripts/diagnose.sh"; capture="$ROOT/scripts/capture.sh"; profile="$ROOT/scripts/profile.sh"; truths="$ROOT/scripts/truths.py"

grep -q 'Cua Driver as the control authority' "$skill" || fail "skill does not name one control authority"
grep -q 'Never retry the same failed delivery shape blindly' "$skill" || fail "skill permits ritual retry"
grep -q 'Never answer a Cua refusal with raw pointer/keyboard injection' "$skill" || fail "skill permits raw-input refusal bypass"
grep -q 'No X11 or XWayland session is' "$skill" || fail "skill lost qualified GNOME session contract"
grep -q 'known app/window | \*\*0\*\*' "$skill" || fail "known-target path lost zero-call budget"
pass "agent hot path delegates mechanics to Cua"

grep -q 'route)' "$profile" || fail "profile route composer missing"
grep -q 'recover)' "$profile" || fail "profile recovery composer missing"
grep -q 'managed)' "$profile" || fail "managed preference surface missing"
grep -q 'truths)' "$profile" || fail "truth status surface missing"
grep -q 'truth_lookup' "$profile" || fail "route does not consume local truth"
grep -q '"$IDENTITY" --resolve --machine' "$profile" || fail "route does not compose deterministic identity locally"
grep -q 'current=$(refresh_profile' "$profile" || fail "recovery does not compose stale-profile refresh locally"
grep -q 'gwcu.route.v1' "$profile" || fail "composed route schema missing"
pass "programs compose recurring mechanics locally"

[ -f "$truths" ] || fail ".gwcu truth helper missing"
grep -q 'SCHEMA = "gwcu.truths.v1"' "$truths" || fail ".gwcu schema is not explicit"
grep -q 'nearest_existing' "$truths" || fail "non-Git ancestor scope resolution missing"
grep -q 'rev-parse.*--show-toplevel' "$truths" || fail "Git-root scope resolution missing"
grep -q '"/.gwcu"' "$truths" || fail "Git ignore protection missing"
grep -q 'GENERATED_SECTIONS' "$truths" || fail "generated truth ownership missing"
pass ".gwcu is a versioned repo/workspace truth contract"

! grep -Eq 'gwcu:desktop-truths|gwcu:app:v1|managed project .*AGENTS|Managed AGENTS' "$ROOT/AGENTS.md" || fail "AGENTS.md still acts as a machine-truth store"
grep -q 'Persistent machine/user truth never belongs in AGENTS.md' "$ROOT/AGENTS.md" || fail "AGENTS truth boundary missing"
pass "AGENTS.md is repository instruction only"

[ ! -f "$ROOT/install-core.sh" ] || fail "runtime-patched installer architecture still exists"
[ ! -f "$ROOT/lib/checks.sh" ] || fail "obsolete shared check library still exists"
grep -q 'GWCU_CUA_DRIVER_RS_VERSION:-0.19.3' "$installer" || fail "Cua version is not qualified"
grep -q 'portal_has RemoteDesktop' "$installer" || fail "RemoteDesktop portal is not a readiness requirement"
grep -q 'portal-control.py.*--authorize' "$installer" || fail "installer does not establish one-time control consent"
grep -q 'GNOME permission prompt may appear in %s' "$installer" || fail "installer lost consent countdown"
grep -q 'Enable managed .gwcu local truths?' "$installer" || fail "installer does not ask managed-truth preference"
grep -q 'scripts/teardown.sh scripts/truths.py' "$installer" || fail "installer does not ship .gwcu machinery"
grep -q 'hermes plugins enable "$NAME"' "$installer" || fail "installer does not enable Hermes command plugin"
! grep -Eq 'add_pkg ydotool|modprobe uinput|usermod .*input|CUA_DRIVER_RS_ENABLE_WAYLAND' "$installer" || fail "installer provisions shadow input"
! grep -Eq 'ExecStart=.*serve\.sh|enable .*gnome-wayland-computer-use\.service' "$installer" || fail "installer owns a Cua daemon"
pass "installation owns one-time setup without adding a second control plane"

grep -q 'managed-agents' "$installer" || fail "installer does not migrate pre-.gwcu preference"
grep -q 'managed-truths' "$installer" || fail "new managed-truth preference is not persistent"
grep -q 'managed-truths' "$teardown" || fail "new managed-truth preference is not reversible"
grep -q 'managed-agents' "$teardown" || fail "legacy preference cleanup missing"
pass "pre-.gwcu installer state migrates cleanly"

grep -q 'doctor_mentions_drm' "$installer" || fail "video group path is not doctor-gated"
grep -q 'adduser "$LOGIN_USER" video' "$installer" || fail "DRM recovery path missing"
grep -q 'gpasswd -d "$LOGIN_USER" video' "$teardown" || fail "DRM recovery is not reversible"
pass "privilege escalation stays evidence-bound"

grep -q -- '--remove-cua' "$uninstaller" || fail "root uninstall cannot reverse provisioned Cua"
grep -q 'distro_foundation_owned.*False' "$installer" || fail "Ubuntu packages are not marked host-owned"
grep -q 'plugins disable "$NAME"' "$teardown" || fail "Hermes plugin is not disabled on teardown"
grep -q 'Repo/workspace .gwcu files' "$teardown" || fail "teardown truth ownership message missing"
pass "teardown distinguishes installer-owned and workspace-owned state"

! grep -Eq 'ydotool|/dev/uinput|org\.cua\.WinRects' "$capture" || fail "observation fallback crosses authority boundary"
grep -q 'org.freedesktop.portal.Screenshot' "$capture" || fail "portal-only direct fallback missing"
pass "observation remains independent without becoming control"

mkdir -p "$TMP/home"
rc=0
HOME="$TMP/home" XDG_SESSION_TYPE=x11 XDG_CURRENT_DESKTOP=KDE "$diagnose" --machine >"$TMP/d.json" || rc=$?
[ "$rc" -ne 0 ] || fail "degraded machine verdict exits zero"
python3 - "$TMP/d.json" <<'PY' || fail "machine verdict schema invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.diagnose.v2'; assert d['ok'] is False; assert d['next']
PY
pass "machine verdict cannot confidently lie"

for doc in README.md GWCU.md CAPABILITIES.md DETERMINISM.md AGENTS.md PERF_NOTES.md; do
    grep -qi 'Cua' "$ROOT/$doc" || fail "$doc lost Cua authority"
    ! grep -Eq 'four-plane|Input recovery' "$ROOT/$doc" || fail "$doc retains obsolete architecture"
done
grep -q 'Four hard advantages' "$ROOT/README.md" || fail "README lost high-level product advantages"
grep -q 'Execution trees' "$ROOT/README.md" || fail "README lost literal execution experience"
grep -q 'Non-Git general workspace' "$ROOT/README.md" || fail "README lost non-Git truth story"
grep -q 'gwcu.truths.v1' "$ROOT/GWCU.md" || fail "public .gwcu contract missing"
pass "documentation shares the final architecture"
printf 'ok - determinism constitution complete\n'
