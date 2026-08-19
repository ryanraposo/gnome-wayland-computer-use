#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)";TMP=$(mktemp -d);trap 'rm -rf "$TMP"' EXIT
SURFACE="$ROOT/scripts/computer-use.sh";WORLD="$ROOT/scripts/worldline.py"
fail(){ printf 'not ok - %s\n' "$1" >&2;exit 1; };pass(){ printf 'ok - %s\n' "$1"; }
cat >"$TMP/fake-cua" <<'PY'
#!/usr/bin/env python3
import json,os,pathlib,socket,sys
log=pathlib.Path(os.environ['FAKE_CUA_LOG']);bg_failed=False
for line in sys.stdin:
 q=json.loads(line);m=q.get('method')
 if m=='initialize': print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'protocolVersion':'2024-11-05'}}),flush=True)
 elif m=='tools/list':
  tools=[{'name':n,'inputSchema':{'type':'object','properties':{'delivery_mode':{'type':'string'},'x':{},'y':{},'text':{},'key':{}}}} for n in ('click','type_text','key_press')]
  print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'tools':tools}}),flush=True)
 elif m=='tools/call':
  name=q['params']['name'];args=q['params']['arguments'];
  with log.open('a') as f:f.write(name+' '+json.dumps(args,separators=(',',':'))+'\n')
  if name=='click' and os.environ.get('EMIT_AFTER_CLICK'):
   s=socket.socket(socket.AF_UNIX);s.connect(os.environ['WORLDLINE_SOCKET']);s.sendall((json.dumps({'op':'event','event':{'source':'test-ui','facts':{'ui.dialog':'ready'}}})+'\n').encode());s.recv(65536);s.close()
  if os.environ.get('BACKGROUND_FAIL_ONCE')=='1' and args.get('delivery_mode')=='background' and not bg_failed:
   bg_failed=True;structured={'ok':False,'code':'background_unavailable','foreground_required':True}
  else:structured={'ok':os.environ.get('FAIL_ON')!=name,'tool':name,'delivery_mode':args.get('delivery_mode')}
  print(json.dumps({'jsonrpc':'2.0','id':q['id'],'result':{'content':[],'isError':False,'structuredContent':structured}}),flush=True)
PY
chmod +x "$TMP/fake-cua"

REQ='{"schema":"gwcu.action-span.request.v1","actions":[{"name":"click","arguments":{"x":10,"y":20}},{"name":"type_text","arguments":{"text":"hello"}},{"name":"key_press","arguments":{"key":"ENTER"}}]}'
FAKE_CUA_LOG="$TMP/calls" XDG_STATE_HOME="$TMP/state" bash "$SURFACE" span --driver "$TMP/fake-cua" --actions-json "$REQ" >"$TMP/result.json"
python3 - "$TMP/result.json" <<'PY' || fail "completed span envelope invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert d['ok'] and d['completed']==3;assert d['control']['mode']=='foreground';assert d['control']['reason']=='standing_preference';assert d['control']['extra_model_calls']==0
assert all(x['control']['applied']=='foreground' for x in d['results'])
PY
pass "default OFF mechanically reaches foreground Cua delivery"

# Regression from the real diagnostic: absence of foreground wording was encoded
# as confidence zero and incorrectly overrode background=OFF. Legacy confidence
# is now accepted but non-authoritative.
REQ_LEGACY_LOW='{"schema":"gwcu.action-span.request.v1","control":{"foreground_confidence":0},"actions":[{"name":"click","arguments":{"x":10,"y":20}}]}'
FAKE_CUA_LOG="$TMP/calls" XDG_STATE_HOME="$TMP/state" bash "$SURFACE" span --driver "$TMP/fake-cua" --actions-json "$REQ_LEGACY_LOW" >"$TMP/legacy-low.json"
python3 - "$TMP/legacy-low.json" <<'PY' || fail "legacy confidence still overrode OFF"
import json,sys
d=json.load(open(sys.argv[1]));c=d['control'];assert c['mode']=='foreground';assert c['reason']=='standing_preference';assert c['legacy_foreground_confidence']==0.0;assert c['legacy_confidence_authoritative'] is False
PY
pass "confidence zero can no longer turn background OFF into invisible execution"

mkdir -p "$TMP/state/gnome-wayland-computer-use";printf 'on\n' >"$TMP/state/gnome-wayland-computer-use/background-priority";: >"$TMP/calls"
REQ_BG='{"schema":"gwcu.action-span.request.v1","control":{"foreground_confidence":1.0},"actions":[{"name":"click","arguments":{"x":10,"y":20}}]}'
FAKE_CUA_LOG="$TMP/calls" XDG_STATE_HOME="$TMP/state" bash "$SURFACE" span --driver "$TMP/fake-cua" --actions-json "$REQ_BG" >"$TMP/bg.json"
python3 - "$TMP/bg.json" <<'PY' || fail "standing background preference not authoritative"
import json,sys
d=json.load(open(sys.argv[1]));assert d['control']['mode']=='background';assert d['control']['reason']=='standing_preference';assert d['results'][0]['control']['applied']=='background'
PY
pass "background ON remains background regardless of legacy confidence"

: >"$TMP/calls";REQ_VISIBLE='{"schema":"gwcu.action-span.request.v1","control":{"visible_required":true},"actions":[{"name":"click","arguments":{"x":10,"y":20}}]}'
FAKE_CUA_LOG="$TMP/calls" XDG_STATE_HOME="$TMP/state" bash "$SURFACE" span --driver "$TMP/fake-cua" --actions-json "$REQ_VISIBLE" >"$TMP/visible.json"
python3 - "$TMP/visible.json" <<'PY' || fail "visible-result intent did not override background preference"
import json,sys
d=json.load(open(sys.argv[1]));c=d['control'];assert c['mode']=='foreground' and c['reason']=='visible_result';assert c['visible_required'] is True;assert c['contradicts_preference'];assert 'switching to foreground' in c['notice'];assert c['extra_model_calls']==0
PY
pass "visible-result intent forces foreground delivery with zero arbitration calls"

: >"$TMP/calls";REQ_EXPLICIT='{"schema":"gwcu.action-span.request.v1","control":{"explicit_mode":"background","visible_required":true},"actions":[{"name":"click","arguments":{"x":10,"y":20}}]}'
FAKE_CUA_LOG="$TMP/calls" XDG_STATE_HOME="$TMP/other-state" bash "$SURFACE" span --driver "$TMP/fake-cua" --actions-json "$REQ_EXPLICIT" >"$TMP/explicit.json"
python3 - "$TMP/explicit.json" <<'PY' || fail "explicit delivery wording did not win"
import json,sys
d=json.load(open(sys.argv[1]));assert d['control']['mode']=='background';assert d['control']['reason']=='explicit_intent'
PY
pass "explicit user delivery wording remains authoritative"

: >"$TMP/calls"
FAKE_CUA_LOG="$TMP/calls" XDG_STATE_HOME="$TMP/state" BACKGROUND_FAIL_ONCE=1 bash "$SURFACE" span --driver "$TMP/fake-cua" --actions-json "$REQ_BG" >"$TMP/fallback.json"
python3 - "$TMP/fallback.json" <<'PY' || fail "runtime foreground fallback invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert d['ok'];assert d['results'][0]['control']['fallback'];assert d['control']['runtime_overrides'][0]['reason']=='cua_background_unavailable';assert d['control']['runtime_notice']
PY
grep -q '"delivery_mode":"background"' "$TMP/calls" && grep -q '"delivery_mode":"foreground"' "$TMP/calls" || fail "Cua fallback did not change delivery mode"
pass "Cua background-unavailable truth falls forward locally once"

mkdir -p "$TMP/runtime";XDG_RUNTIME_DIR="$TMP/runtime" GWCU_WORLDLINE_IDLE_SECONDS=30 python3 "$WORLD" serve >/dev/null 2>&1 & wpid=$!
for _ in $(seq 1 50);do [ -S "$TMP/runtime/gnome-wayland-computer-use/worldline.sock" ]&&break;sleep .02;done
SOCK="$TMP/runtime/gnome-wayland-computer-use/worldline.sock";: >"$TMP/calls"
TX='{"schema":"gwcu.transaction.v1","steps":[{"action":{"name":"click","arguments":{"x":10,"y":20}},"await":{"timeout_ms":1000,"predicates":[{"path":"ui.dialog","op":"eq","value":"ready"}]}},{"action":{"name":"type_text","arguments":{"text":"continued locally"}}}]}'
FAKE_CUA_LOG="$TMP/calls" EMIT_AFTER_CLICK=1 WORLDLINE_SOCKET="$SOCK" XDG_RUNTIME_DIR="$TMP/runtime" XDG_STATE_HOME="$TMP/other-state" bash "$SURFACE" span --driver "$TMP/fake-cua" --worldline-socket "$SOCK" --actions-json "$TX" >"$TMP/tx.json"
python3 - "$TMP/tx.json" <<'PY' || fail "transaction envelope invalid"
import json,sys
d=json.load(open(sys.argv[1]));assert d['ok'] and d['completed']==2;assert d['results'][0]['worldline']['code']=='ready'
PY
pass "one outer call performs Cua action -> WORLDLINE wait -> local continuation"
XDG_RUNTIME_DIR="$TMP/runtime" python3 "$WORLD" request --json '{"op":"close"}' >/dev/null||true;wait "$wpid"||true
! grep -Eq 'ydotool|uinput|org\.cua\.WinRects' "$SURFACE" || fail "span surface bypasses Cua authority"
pass "transaction executor preserves Cua as sole actuator"
