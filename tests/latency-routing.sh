#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }
observer="$ROOT/scripts/observer.py"; observe="$ROOT/scripts/observe.sh"; capture="$ROOT/scripts/capture.sh"; skill="$ROOT/SKILL.md"; profile="$ROOT/scripts/profile.sh"

grep -q 'DEFAULT_IDLE' "$observer" || fail "observer lost bounded warm lifetime"
grep -q 'pipewire-serial' "$observer" || fail "observer lost ScreenCast v6 targeting"
grep -q 'target-object' "$observer" || fail "observer lost PipeWire serial preference"
grep -q 'SocketMode=0600' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer socket is not private"
grep -q 'DirectoryMode=0700' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer directory is not private"
pass "warm observer remains lazy, private and v6-aware"

grep -q 'broker_capture' "$observe" || fail "observe facade lost broker hot path"
grep -q 'DIRECT_CAPTURE' "$observe" || fail "observe facade lost process fallback"
! grep -Eq 'ydotool|uinput' "$capture" || fail "direct observation fallback injects input"
pass "observation fallback cannot mutate foreground through raw input"

mkdir -p "$TMP/bin"
cat >"$TMP/fake-observer.py" <<'PY'
import json
print(json.dumps({'schema':'gwcu.observer.v1','ok':False,'code':'broker_unavailable','retryable':True,'terminal':False,'next':{'action':'start_observer_socket'}},separators=(',',':')))
raise SystemExit(30)
PY
cat >"$TMP/direct" <<'SH'
#!/usr/bin/env bash
printf png > "$2"; printf 'capture_method=portal-screenshot\n'
SH
cat >"$TMP/bin/systemctl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP/direct" "$TMP/bin/systemctl"
PATH="$TMP/bin:/usr/bin:/bin" GWCU_OBSERVER_BIN="$TMP/fake-observer.py" GWCU_DIRECT_CAPTURE_BIN="$TMP/direct" GNOME_WAYLAND_SYSTEM_PYTHON=/usr/bin/python3 \
    "$observe" --machine --screen "$TMP/screen.png" >"$TMP/observe.json"
python3 - "$TMP/observe.json" <<'PY' || fail "direct fallback envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok']; assert d['result']['method']=='portal-screenshot-direct'
PY
pass "broker transport failure falls through once"

cat >"$TMP/denied.py" <<'PY'
import json
print(json.dumps({'schema':'gwcu.observer.v1','ok':False,'code':'portal_cancelled','retryable':False,'terminal':True,'next':None},separators=(',',':')))
raise SystemExit(20)
PY
cat >"$TMP/must-not" <<'SH'
#!/usr/bin/env bash
touch "$HOME/direct-called"; exit 1
SH
chmod +x "$TMP/must-not"; mkdir -p "$TMP/home"
rc=0
HOME="$TMP/home" PATH="$TMP/bin:/usr/bin:/bin" GWCU_OBSERVER_BIN="$TMP/denied.py" GWCU_DIRECT_CAPTURE_BIN="$TMP/must-not" GNOME_WAYLAND_SYSTEM_PYTHON=/usr/bin/python3 \
    "$observe" --machine --screen "$TMP/no.png" >"$TMP/deny.json" || rc=$?
[ "$rc" -eq 20 ] || fail "portal cancellation lost terminal exit class"
[ ! -e "$TMP/home/direct-called" ] || fail "portal cancellation opened another capture path"
pass "consent cancellation is terminal"

# One uncertain-target call may compose local memory + identity + cached profile,
# but it must not wake diagnostics merely because identity is uncertain.
cat >"$TMP/identity" <<'SH'
#!/usr/bin/env bash
[ ! -n "${IDENTITY_CALLED_FILE:-}" ] || : > "$IDENTITY_CALLED_FILE"
printf '%s\n' '{"schema":"gwcu.identity.v1","ok":true,"code":"resolved","result":{"display_name":"ChatGPT","desktop_id":"chatgpt.desktop","app_id":"chatgpt_app","startup_wm_class":"crx_chatgpt_app","kind":"installed-web-app"},"evidence":["exact_display_name"],"next":{"action":"use_identity"}}'
SH
cat >"$TMP/diagnose" <<'SH'
#!/usr/bin/env bash
touch "$XDG_STATE_HOME/diagnose-called"
printf '%s\n' '{"schema":"gwcu.diagnose.v2","ok":true,"code":"ready","next":null}'
SH
chmod +x "$TMP/identity" "$TMP/diagnose"
mkdir -p "$TMP/route-home" "$TMP/route-state" "$TMP/project"
printf '# User project instructions\n\nKeep this exact text.\n' > "$TMP/project/AGENTS.md"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_PROJECT_ROOT="$TMP/project" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" \
    IDENTITY_CALLED_FILE="$TMP/identity-first" \
    "$profile" route --machine ChatGPT >"$TMP/route.json"
python3 - "$TMP/route.json" <<'PY' || fail "one-call target route envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.route.v1'; assert d['ok']; assert d['code']=='target_resolved'; assert d['next']['action']=='cua_target_state'; assert d['host']['cached'] is False
assert d['project_memory']['code']=='recorded'; assert d['project_memory']['changed'] is True
PY
[ -e "$TMP/identity-first" ] || fail "cold route did not consult deterministic identity resolver"
[ ! -e "$TMP/route-state/diagnose-called" ] || fail "target routing paid for diagnostics"
grep -q '^# User project instructions$' "$TMP/project/AGENTS.md" || fail "managed memory damaged user AGENTS content"
grep -q '^<!-- gwcu:desktop-truths:v1:start -->$' "$TMP/project/AGENTS.md" || fail "managed AGENTS start marker missing"
grep -Eq '^<!-- gwcu:app:v1 \{.*"desktop_id":"chatgpt\.desktop".*\} -->$' "$TMP/project/AGENTS.md" || fail "stable app truth is not regex-addressable"
! grep -Eqi 'timestamp|updated_at|window.*(x|y|width|height)' "$TMP/project/AGENTS.md" || fail "managed AGENTS truth contains volatile state"
pass "cold route records a tiny stable project truth without diagnostics"

# The next route must hit project AGENTS memory and skip the launcher resolver.
rm -f "$TMP/identity-second"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_PROJECT_ROOT="$TMP/project" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" \
    IDENTITY_CALLED_FILE="$TMP/identity-second" \
    "$profile" route --machine ChatGPT >"$TMP/route-hit.json"
python3 - "$TMP/route-hit.json" <<'PY' || fail "project-memory route envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok']; assert d['code']=='target_resolved'; assert d['next']['identity_source']=='project_agents'; assert d['evidence']==['project_agents_truth']; assert d['project_memory']['code']=='hit'
PY
[ ! -e "$TMP/identity-second" ] || fail "project-memory hit still scanned launchers"
[ "$(grep -c '^<!-- gwcu:app:v1 ' "$TMP/project/AGENTS.md")" -eq 1 ] || fail "repeat route churned managed truth"
pass "project AGENTS truth eliminates repeat identity scans inside the same one-call route"

# Opt-out must preserve project files and continue to deterministic launcher resolution.
cp "$TMP/project/AGENTS.md" "$TMP/agents-before"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_PROJECT_ROOT="$TMP/project" GWCU_PROJECT_MEMORY=off \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" \
    IDENTITY_CALLED_FILE="$TMP/identity-optout" \
    "$profile" route --machine ChatGPT >"$TMP/route-optout.json"
[ -e "$TMP/identity-optout" ] || fail "project-memory opt-out did not fall back to identity resolver"
cmp -s "$TMP/agents-before" "$TMP/project/AGENTS.md" || fail "project-memory opt-out mutated AGENTS.md"
pass "project memory is locally disableable without changing routing semantics"

# Recovery is the deliberate expensive path. The outer agent still pays one call:
# profile.sh composes read -> refresh -> diagnose locally when cached state is absent.
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" \
    "$profile" recover --machine >"$TMP/recover.json"
python3 - "$TMP/recover.json" <<'PY' || fail "one-call recovery envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.route.v1'; assert d['ok']; assert d['code']=='host_ready'; assert d['source']=='refreshed'
PY
[ -e "$TMP/route-state/diagnose-called" ] || fail "recovery did not compose diagnostic refresh"
pass "one recovery call composes read, refresh and diagnose locally"

grep -q 'known app/window | \*\*0\*\*' "$skill" || fail "skill lost zero-call known-target budget"
grep -q 'project AGENTS truth lookup' "$skill" || fail "skill does not consume project-local stable truth"
grep -q 'Do not make the model perform `read → refresh → diagnose`' "$skill" || fail "skill permits model-driven diagnostic fanout"
for primitive in clarify execute_code delegate_task 'notify_on_complete=true'; do
    grep -q "$primitive" "$skill" || fail "skill does not leverage Hermes primitive: $primitive"
done
pass "agent call-budget, project-memory and Hermes orchestration contracts are explicit"