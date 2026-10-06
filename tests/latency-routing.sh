#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }; pass(){ printf 'ok - %s\n' "$1"; }
observer="$ROOT/scripts/observer.py"; observe="$ROOT/scripts/observe.sh"; capture="$ROOT/scripts/capture.sh"
skill="$ROOT/SKILL.md"; profile="$ROOT/scripts/profile.sh"; truths="$ROOT/scripts/truths.py"; portal="$ROOT/scripts/portal-control.py"

grep -q 'DEFAULT_IDLE' "$observer" || fail "observer lost bounded warm lifetime"
grep -q 'SocketMode=0600' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer socket is not private"
grep -q 'DirectoryMode=0700' "$ROOT/systemd/user/gnome-wayland-computer-use-observer.socket" || fail "observer directory is not private"
grep -q 'broker_capture' "$observe" || fail "observe facade lost broker hot path"
! grep -Eq 'ydotool|uinput' "$capture" || fail "observation fallback injects input"
pass "observation remains warm, private and control-free"

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
printf '%s\n' '{"schema":"gwcu.diagnose.v2","ok":true,"code":"ready","host":{"session":"wayland","desktop":"GNOME","ok":true},"observation":{"status":"ready"},"cua":{"status":"ready"},"next":null}'
SH
chmod +x "$TMP/identity" "$TMP/diagnose"
mkdir -p "$TMP/route-home" "$TMP/route-state" "$TMP/project/work"
git -C "$TMP/project" init -q
printf '# User ignore rules\nnode_modules/\n' >"$TMP/project/.gitignore"
printf '# User project instructions\n\nKeep this exact text.\n' >"$TMP/project/AGENTS.md"

HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_WORKDIR="$TMP/project/work" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/identity-first" \
    "$profile" route --machine ChatGPT >"$TMP/route.json"
python3 - "$TMP/route.json" <<'PY' || fail "cold route envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.route.v1'; assert d['ok']; assert d['code']=='target_resolved'
assert d['truths']['code']=='recorded'; assert d['truths']['changed'] is True
PY
[ -e "$TMP/identity-first" ] || fail "cold route skipped identity resolver"
[ ! -e "$TMP/route-state/diagnose-called" ] || fail "target route paid for diagnostics"
[ -f "$TMP/project/.gwcu" ] || fail "Git-scope .gwcu was not created"
grep -qx '/\.gwcu' "$TMP/project/.gitignore" || fail "Git-scope .gwcu is not root-ignored"
grep -qx 'node_modules/' "$TMP/project/.gitignore" || fail "existing .gitignore content was damaged"
grep -q '^# User project instructions$' "$TMP/project/AGENTS.md" || fail "routing damaged AGENTS.md"
! grep -q 'gwcu:' "$TMP/project/AGENTS.md" || fail "routing still writes GWCU truth into AGENTS.md"
python3 - "$TMP/project/.gwcu" <<'PY' || fail ".gwcu cold-write contract invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.truths.v1'; assert d['apps']['chatgpt.desktop']['app_id']=='chatgpt_app'
assert set(('observed','capabilities','calibration','preferences','apps')).issubset(d)
assert 'timestamp' not in open(sys.argv[1]).read().lower()
PY
pass "cold route records stable truth in ignored repo-local .gwcu"

rm -f "$TMP/identity-second"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_WORKDIR="$TMP/project/work" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/identity-second" \
    "$profile" route --machine ChatGPT >"$TMP/route-hit.json"
python3 - "$TMP/route-hit.json" <<'PY' || fail "warm route envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok']; assert d['next']['identity_source']=='gwcu'
assert d['evidence']==['gwcu_truth']; assert d['truths']['code']=='hit'
PY
[ ! -e "$TMP/identity-second" ] || fail "warm .gwcu truth still scanned launchers"
pass "warm .gwcu hit skips repeat identity resolution"

# Managed-off must bypass persisted truth without deleting workspace state.
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_WORKDIR="$TMP/project/work" "$profile" managed off --machine >"$TMP/managed-off.json"
python3 - "$TMP/managed-off.json" <<'PY' || fail "managed preference envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['managed_truths'] is False; assert d['code']=='managed_truths_off'
assert d['max_repeat_identity_resolution_savings_percent']==100
PY
cp "$TMP/project/.gwcu" "$TMP/gwcu-before"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_WORKDIR="$TMP/project/work" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/identity-pref-off" \
    "$profile" route --machine ChatGPT >"$TMP/route-pref-off.json"
[ -e "$TMP/identity-pref-off" ] || fail "managed-off preference did not bypass .gwcu"
cmp -s "$TMP/gwcu-before" "$TMP/project/.gwcu" || fail "managed-off route mutated .gwcu"
pass "managed-off bypasses persisted truth without destroying it"

HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_WORKDIR="$TMP/project/work" "$profile" managed on --machine >/dev/null
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_WORKDIR="$TMP/project/work" GWCU_TRUTHS=off \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/identity-env-off" \
    "$profile" route --machine ChatGPT >/dev/null
[ -e "$TMP/identity-env-off" ] || fail "GWCU_TRUTHS=off did not override persistent preference"
pass "runtime truth override remains authoritative"

# If a Git scope cannot safely establish .gitignore, persistence must fail closed.
mkdir -p "$TMP/unsafe/work" "$TMP/unsafe-target"
git -C "$TMP/unsafe" init -q
ln -s "$TMP/unsafe-target/ignore" "$TMP/unsafe/.gitignore"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/route-state" GWCU_WORKDIR="$TMP/unsafe/work" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" \
    "$profile" route --machine ChatGPT >"$TMP/unsafe-route.json"
[ ! -e "$TMP/unsafe/.gwcu" ] || fail ".gwcu was written without safe Git ignore protection"
python3 - "$TMP/unsafe-route.json" <<'PY' || fail "unsafe-ignore route envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok']; assert d['code']=='target_resolved'; assert d['truths']['code']=='gitignore_symlink_refused'
PY
pass "Git truth write fails closed when ignore protection is unsafe"

# Non-Git workspace: seed once at the workspace root; descendants reuse nearest .gwcu.
mkdir -p "$TMP/general/scratch/today" "$TMP/general/experiments"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/general-state" GWCU_WORKDIR="$TMP/general" "$profile" managed on --machine >/dev/null
[ -f "$TMP/general/.gwcu" ] || fail "managed on did not seed non-Git workspace truth"
[ ! -e "$TMP/general/.gitignore" ] || fail "non-Git workspace received unnecessary .gitignore"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/general-state" GWCU_WORKDIR="$TMP/general/scratch/today" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/general-first" \
    "$profile" route --machine ChatGPT >"$TMP/general-route.json"
python3 - "$TMP/general-route.json" <<'PY' || fail "non-Git route invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['truths']['root'].endswith('/general'); assert d['truths']['source']=='nearest_truth'
PY
rm -f "$TMP/general-second"
HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/general-state" GWCU_WORKDIR="$TMP/general/experiments" \
    GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" IDENTITY_CALLED_FILE="$TMP/general-second" \
    "$profile" route --machine ChatGPT >"$TMP/general-hit.json"
[ ! -e "$TMP/general-second" ] || fail "sibling non-Git workspace did not reuse ancestor truth"
pass "nearest .gwcu makes non-Git general workspaces first-class"

# Regeneration clears generated truth but preserves preferences and extensions.
GWCU_WORKDIR="$TMP/general" python3 "$truths" merge --section preferences --json '{"preserve_foreground":true}' >/dev/null
python3 - "$TMP/general/.gwcu" <<'PY'
import json,sys
p=sys.argv[1]; d=json.load(open(p)); d['example_extension']={'enabled':True}; open(p,'w').write(json.dumps(d,indent=2,sort_keys=True)+'\n')
PY
GWCU_WORKDIR="$TMP/general" python3 "$truths" regenerate >/dev/null
python3 - "$TMP/general/.gwcu" <<'PY' || fail "truth regeneration ownership invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['preferences']['preserve_foreground'] is True; assert d['example_extension']['enabled'] is True
for key in ('observed','capabilities','calibration','apps'): assert d[key]=={}
PY
pass "generated truth can regenerate without erasing preferences/extensions"

HOME="$TMP/route-home" XDG_STATE_HOME="$TMP/recover-state" GWCU_IDENTITY_BIN="$TMP/identity" GWCU_DIAGNOSE_BIN="$TMP/diagnose" \
    "$profile" recover --machine >"$TMP/recover.json"
python3 - "$TMP/recover.json" <<'PY' || fail "recovery envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.route.v1'; assert d['ok']; assert d['code']=='host_ready'; assert d['source']=='refreshed'
PY
[ -e "$TMP/recover-state/diagnose-called" ] || fail "recovery did not compose diagnosis"
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
        name=q['params']['name']; log.write_text((log.read_text() if log.exists() else '')+name+'\n')
        if name=='get_screen_size': result={'width':1200,'height':800}
        elif name=='move_cursor': pathlib.Path(os.environ['GWCU_LIBEI_TOKEN']).write_text('restore-token'); result={'ok':True}
        else: result={}
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'content':[],'isError':False,'structuredContent':result}}),flush=True)
PY
chmod +x "$TMP/fake-cua"
GWCU_REMOTE_DESKTOP_AVAILABLE=1 GWCU_LIBEI_TOKEN="$TMP/libei.token" FAKE_CUA_LOG="$TMP/cua.calls" \
    "$portal" --authorize --driver "$TMP/fake-cua" >"$TMP/portal.json"
python3 - "$TMP/portal.json" <<'PY' || fail "portal bootstrap envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok']; h=d['handshake']; assert h['operation']=='move_cursor'; assert h['click'] is False; assert h['key'] is False
PY
! grep -Eqi 'click|type|key' "$TMP/cua.calls" || fail "portal bootstrap emitted invasive input"
pass "install-time RemoteDesktop bootstrap is pointer-only"

plugin="$ROOT/runtimes/hermes/__init__.py"
! grep -Fq 'ctx.register_command(' "$plugin" || fail "Hermes plugin shadows the native computer-use skill command"
grep -Fq '/computer-use <task>' "$skill" || fail "skill-native task invocation is missing"
for word in status background managed truths consent doctor help; do grep -Fq "\`$word\`" "$skill" || fail "reserved computer-use subcommand lost $word"; done
pass "Hermes skill owns task and subcommand slash routing"

grep -q 'known app/window | \*\*0\*\*' "$skill" || fail "skill lost zero-call known-target budget"
grep -q 'repo/workspace .gwcu lookup' "$skill" || fail "skill does not consume .gwcu before identity discovery"
grep -q 'Do not make the model perform `read → refresh → diagnose`' "$skill" || fail "skill permits model diagnostic fanout"
pass "agent call-budget and truth contracts are explicit"
