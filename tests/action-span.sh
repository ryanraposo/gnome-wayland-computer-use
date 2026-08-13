#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SPAN="$ROOT/scripts/action-span.py"
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

cat >"$TMP/fake-cua" <<'PY'
#!/usr/bin/env python3
import json,os,pathlib,sys
log=pathlib.Path(os.environ['FAKE_CUA_LOG'])
for line in sys.stdin:
    q=json.loads(line)
    if q.get('method')=='initialize':
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'protocolVersion':'2024-11-05','serverInfo':{'name':'fake-cua','version':'test'}}}),flush=True)
    elif q.get('method')=='tools/call':
        name=q['params']['name']
        with log.open('a',encoding='utf-8') as f: f.write(name+'\n')
        if os.environ.get('FAIL_ON')==name:
            result={'content':[],'isError':False,'structuredContent':{'ok':False,'code':'refused_for_test'}}
        else:
            result={'content':[],'isError':False,'structuredContent':{'ok':True,'tool':name}}
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':result}),flush=True)
PY
chmod +x "$TMP/fake-cua"

REQ='{"schema":"gwcu.action-span.request.v1","actions":[{"name":"click","arguments":{"x":10,"y":20}},{"name":"type_text","arguments":{"text":"hello"}},{"name":"key_press","arguments":{"key":"ENTER"}}]}'
FAKE_CUA_LOG="$TMP/calls" "$SPAN" --driver "$TMP/fake-cua" --actions-json "$REQ" >"$TMP/result.json"
python3 - "$TMP/result.json" <<'PY' || fail "completed span envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['schema']=='gwcu.action-span.v1'; assert d['ok']; assert d['code']=='completed'; assert d['requested']==3; assert d['completed']==3; assert d['boundary'] is None
assert [x['name'] for x in d['results']]==['click','type_text','key_press']
PY
[ "$(wc -l < "$TMP/calls")" -eq 3 ] || fail "span did not execute every predetermined action"
printf 'click\ntype_text\nkey_press\n' | cmp -s - "$TMP/calls" || fail "span changed action order"
pass "one outer invocation executes the complete predetermined action span in order"

: >"$TMP/calls"
rc=0
FAKE_CUA_LOG="$TMP/calls" FAIL_ON=type_text "$SPAN" --driver "$TMP/fake-cua" --actions-json "$REQ" >"$TMP/boundary.json" || rc=$?
[ "$rc" -eq 30 ] || fail "Cua failure did not return boundary exit class"
python3 - "$TMP/boundary.json" <<'PY' || fail "boundary envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert not d['ok']; assert d['code']=='boundary'; assert d['requested']==3; assert d['completed']==1
assert d['boundary']['index']==1 and d['boundary']['name']=='type_text'; assert d['boundary']['reason']=='cua_failure'
PY
printf 'click\ntype_text\n' | cmp -s - "$TMP/calls" || fail "span executed beyond a Cua decision boundary"
pass "span stops immediately when Cua creates a real decision boundary"

python3 - "$SPAN" <<'PY' || fail "action-span Python syntax invalid"
PY

grep -q 'one model/tool boundary' "$SPAN" || fail "runner does not state its boundary contract"
! grep -Eq 'ydotool|uinput|org\.cua\.WinRects' "$SPAN" || fail "runner bypasses Cua control authority"
pass "action-span runner remains a thin Cua composition layer"
