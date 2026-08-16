#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SURFACE="$ROOT/scripts/computer-use.sh"; WORLD="$ROOT/scripts/worldline.py"
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

cat >"$TMP/fake-cua" <<'PY'
#!/usr/bin/env python3
import json,os,pathlib,socket,sys
log=pathlib.Path(os.environ['FAKE_CUA_LOG'])
for line in sys.stdin:
    q=json.loads(line)
    if q.get('method')=='initialize':
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'protocolVersion':'2024-11-05','serverInfo':{'name':'fake-cua','version':'test'}}}),flush=True)
    elif q.get('method')=='tools/call':
        name=q['params']['name']
        with log.open('a',encoding='utf-8') as f: f.write(name+'\n')
        if name=='click' and os.environ.get('EMIT_AFTER_CLICK'):
            s=socket.socket(socket.AF_UNIX); s.connect(os.environ['WORLDLINE_SOCKET'])
            s.sendall((json.dumps({'op':'event','event':{'source':'test-ui','facts':{'ui.dialog':'ready'}}})+'\n').encode())
            s.recv(65536); s.close()
        result={'content':[],'isError':False,'structuredContent':{'ok':os.environ.get('FAIL_ON')!=name,'tool':name}}
        print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':result}),flush=True)
PY
chmod +x "$TMP/fake-cua"

REQ='{"schema":"gwcu.action-span.request.v1","actions":[{"name":"click","arguments":{"x":10,"y":20}},{"name":"type_text","arguments":{"text":"hello"}},{"name":"key_press","arguments":{"key":"ENTER"}}]}'
FAKE_CUA_LOG="$TMP/calls" bash "$SURFACE" span --driver "$TMP/fake-cua" --actions-json "$REQ" >"$TMP/result.json"
python3 - "$TMP/result.json" <<'PY' || fail "completed span envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok'] and d['code']=='completed' and d['completed']==3
PY
printf 'click\ntype_text\nkey_press\n' | cmp -s - "$TMP/calls" || fail "legacy span order changed"
pass "legacy predetermined action spans remain compatible"

mkdir -p "$TMP/runtime"
XDG_RUNTIME_DIR="$TMP/runtime" GWCU_WORLDLINE_IDLE_SECONDS=30 python3 "$WORLD" serve >/dev/null 2>&1 &
wpid=$!
for _ in $(seq 1 50); do [ -S "$TMP/runtime/gnome-wayland-computer-use/worldline.sock" ] && break; sleep .02; done
SOCK="$TMP/runtime/gnome-wayland-computer-use/worldline.sock"

: >"$TMP/calls"
TX='{"schema":"gwcu.transaction.v1","steps":[{"action":{"name":"click","arguments":{"x":10,"y":20}},"await":{"timeout_ms":1000,"predicates":[{"path":"ui.dialog","op":"eq","value":"ready"}]}},{"action":{"name":"type_text","arguments":{"text":"continued locally"}}}]}'
FAKE_CUA_LOG="$TMP/calls" EMIT_AFTER_CLICK=1 WORLDLINE_SOCKET="$SOCK" XDG_RUNTIME_DIR="$TMP/runtime" bash "$SURFACE" span --driver "$TMP/fake-cua" --worldline-socket "$SOCK" --actions-json "$TX" >"$TMP/tx.json"
python3 - "$TMP/tx.json" <<'PY' || fail "transaction envelope invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d['ok'] and d['completed']==2
assert d['results'][0]['worldline']['code']=='ready'
PY
printf 'click\ntype_text\n' | cmp -s - "$TMP/calls" || fail "transaction did not continue locally after predicate"
pass "one outer call performs Cua action -> WORLDLINE wait -> local continuation"

XDG_RUNTIME_DIR="$TMP/runtime" python3 "$WORLD" request --json '{"op":"close"}' >/dev/null || true
wait "$wpid" || true

grep -q 'ONE model/tool boundary' "$SURFACE" || fail "installed surface does not state boundary contract"
! grep -Eq 'ydotool|uinput|org\.cua\.WinRects' "$SURFACE" || fail "span surface bypasses Cua control authority"
pass "transaction executor preserves Cua as the sole actuator"
