#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }
observer="$ROOT/scripts/observer.py"; observe="$ROOT/scripts/observe.sh"; capture="$ROOT/scripts/capture.sh"
skill="$ROOT/SKILL.md"; profile="$ROOT/scripts/profile.sh"; portal="$ROOT/scripts/portal-control.py"

grep -q 'DEFAULT_IDLE' "$observer" || fail "observer lost bounded warm lifetime"
grep -q 'pipewire-serial' "$observer" || fail "observer lost ScreenCast v6 targeting"
grep -q 'SocketMode=0600' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer socket is not private"
grep -q 'DirectoryMode=0700' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer directory is not private"
pass "warm observer remains lazy and private"

grep -q 'broker_capture' "$observe" || fail "observe facade lost broker hot path"
grep -q 'DIRECT_CAPTURE' "$observe" || fail "observe facade lost direct fallback"
! grep -Eq 'ydotool|uinput' "$capture" || fail "observation fallback injects input"
pass "observation remains control-free"

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

cat >"$TMP/identity" <<'SH'
#!/usr/bin/env bash
[ -z "${IDENTITY_CALLED_FILE:-}" ] || : > "$IDENTITY_CALLED_FILE"
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
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/identity-first" \
    "$profile" route --machine ChatGPT >"$TMP/route.json"
python3 - "$TMP/route.json" <<'PY' || fail "cold route envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.route.v1'; assert d['ok']; assert d['code']=='target_resolved'
assert d['project_memory']['code']=='recorded'; assert d['project_memory']['changed'] is True
PY
[ -e "$TMP/identity-first" ] || fail "cold route skipped identity resolver"
[ ! -e "$TMP/route-state/diagnose-called" ] || fail "target route paid for diagnostics"
grep -q '^# User project instructions$' "$TMP/project/AGENTS.md" || fail "managed memory damaged user AGENTS content"
grep -q '^<!-- gwcu:desktop-truths:v1:start -->$' "$TMP/project/AGENTS.md" || fail "managed start marker missing"
grep -Eq '^<!-- gwcu:app:v1 \{.*"desktop_id":"chatgpt\.desktop".*\} -->$' "$TMP/project/AGENTS.md" || fail "truth is not regex-addressable"
! grep -Eqi 'timestamp|updated_at|window.*(x|y|width|height)' "$TMP/project/AGENTS.md" || fail "managed truth contains volatile state"
pass "cold route records bounded stable project truth"

rm -f "$TMP/identity-second"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_PROJECT_ROOT="$TMP/project" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/identity-second" \
    "$profile" route --machine ChatGPT >"$TMP/route-hit.json"
python3 - "$TMP/route-hit.json" <<'PY' || fail "warm route envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok']; assert d['next']['identity_source']=='project_agents'
assert d['evidence']==['project_agents_truth']; assert d['project_memory']['code']=='hit'
PY
[ ! -e "$TMP/identity-second" ] || fail "warm project truth still scanned launchers"
[ "$(grep -c '^<!-- gwcu:app:v1 ' "$TMP/project/AGENTS.md")" -eq 1 ] || fail "warm hit churned truth"
pass "managed project truth skips repeat identity resolution"

# Persistent installer/user preference must disable write-back without an env override.
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" "$profile" managed off --machine >"$TMP/managed-off.json"
python3 - "$TMP/managed-off.json" <<'PY' || fail "managed preference envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['managed_agents'] is False; assert d['code']=='managed_agents_off'
assert d['max_repeat_identity_route_setup_savings_percent']==100
PY
cp "$TMP/project/AGENTS.md" "$TMP/agents-before"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_PROJECT_ROOT="$TMP/project" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/identity-pref-off" \
    "$profile" route --machine ChatGPT >"$TMP/route-pref-off.json"
[ -e "$TMP/identity-pref-off" ] || fail "persistent managed-off preference did not bypass project truth"
cmp -s "$TMP/agents-before" "$TMP/project/AGENTS.md" || fail "managed-off preference mutated AGENTS"
pass "managed AGENTS preference persists outside the model loop"

HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" "$profile" managed on --machine >/dev/null
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_PROJECT_ROOT="$TMP/project" GWCU_PROJECT_MEMORY=off \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/identity-env-off" \
    "$profile" route --machine ChatGPT >/dev/null
[ -e "$TMP/identity-env-off" ] || fail "environment opt-out did not override persistent preference"
pass "runtime environment override remains authoritative"

HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" \
    "$profile" recover --machine >"$TMP/recover.json"
python3 - "$TMP/recover.json" <<'PY' || fail "recovery envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.route.v1'; assert d['ok']; assert d['code']=='host_ready'; assert d['source']=='refreshed'
PY
[ -e "$TMP/route-state/diagnose-called" ] || fail "recovery did not compose diagnosis"
pass "one recovery call composes read, refresh and diagnose locally"

# Portal bootstrap must use only get_screen_size + move_cursor, never click/type.
cat >"$TMP/fake-cua" <<'PY'
#!/usr/bin/env python3
import json,os,pathlib,sys
log=pathlib.Path(os.environ['FAKE_CUA_LOG'])
for line in sys.stdin:
    q=json.loads(line)
    if q.get('method')=='initialize':
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'protocolVersion':'2024-11-05','serverInfo':{'name':'fake','version':'1'}}}),flush=True)
    elif q.get('method')=='tools/call':
        name=q['params']['name']
        log.write_text((log.read_text() if log.exists() else '')+name+'\n')
        if name=='get_screen_size':
            result={'width':1200,'height':800}
        elif name=='move_cursor':
            pathlib.Path(os.environ['GWCU_LIBEI_TOKEN']).write_text('restore-token')
            result={'ok':True}
        else:
            result={}
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'content':[],'isError':False,'structuredContent':result}}),flush=True)
PY
chmod +x "$TMP/fake-cua"
GWCU_REMOTE_DESKTOP_AVAILABLE=1 GWCU_LIBEI_TOKEN="$TMP/libei.token" FAKE_CUA_LOG="$TMP/cua.calls" \
    "$portal" --authorize --driver "$TMP/fake-cua" >"$TMP/portal.json"
python3 - "$TMP/portal.json" <<'PY' || fail "portal bootstrap envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok']; assert d['code']=='authorized'
h=d['handshake']; assert h['operation']=='move_cursor'; assert h['click'] is False; assert h['key'] is False
assert d['portal']['restore_token']['present'] is True
PY
grep -qx 'get_screen_size' "$TMP/cua.calls" || fail "portal bootstrap did not query size"
grep -qx 'move_cursor' "$TMP/cua.calls" || fail "portal bootstrap did not perform pointer-only handshake"
! grep -Eqi 'click|type|key' "$TMP/cua.calls" || fail "portal bootstrap emitted invasive input"
pass "install-time RemoteDesktop bootstrap is pointer-only"

plugin="$ROOT/runtimes/hermes/__init__.py"
grep -q 'register_command' "$plugin" || fail "Hermes plugin does not register a native slash command"
grep -q '"computer-use"' "$plugin" || fail "Hermes /computer-use command missing"
for word in status managed consent doctor; do grep -q "$word" "$plugin" || fail "Hermes command hint lost $word"; done
pass "Hermes /computer-use is native and discoverable"

grep -q 'known app/window | \*\*0\*\*' "$skill" || fail "skill lost zero-call known-target budget"
grep -q 'project AGENTS truth lookup' "$skill" || fail "skill does not consume stable project truth"
grep -q 'Do not make the model perform `read → refresh → diagnose`' "$skill" || fail "skill permits model diagnostic fanout"
for primitive in clarify execute_code delegate_task 'notify_on_complete=true'; do
    grep -q "$primitive" "$skill" || fail "skill does not leverage Hermes primitive: $primitive"
done
pass "agent call-budget, memory and orchestration contracts are explicit"
