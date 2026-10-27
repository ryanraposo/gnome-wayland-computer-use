#!/usr/bin/env bash
# Cross-repository socket acceptance, using the actual standalone dispatcher.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORLDLINE_SOURCE="${WORLDLINE_SOURCE:-$ROOT/../WORLDLINE}"
TMP="$(mktemp -d)"
trap 'kill "$server" 2>/dev/null || true' EXIT
[ -f "$WORLDLINE_SOURCE/src/worldline/daemon.py" ] || {
  printf 'WORLDLINE_SOURCE must name the standalone repository\n' >&2; exit 2;
}
export PYTHONPATH="$WORLDLINE_SOURCE/src"
export WORLDLINE_SOCKET="$TMP/worldline.sock"
python3 - "$WORLDLINE_SOCKET" <<'PY' &
import asyncio,sys
from worldline.daemon import WorldlineDaemon
async def main():
    daemon=WorldlineDaemon()
    server=await asyncio.start_unix_server(daemon.handle,path=sys.argv[1])
    async with server: await server.serve_forever()
asyncio.run(main())
PY
server=$!
for _ in $(seq 1 100); do [ -S "$WORLDLINE_SOCKET" ] && break; sleep .02; done
[ -S "$WORLDLINE_SOCKET" ] || { printf 'standalone socket did not start\n' >&2; exit 1; }
python3 "$ROOT/scripts/worldline.py" self-test >/dev/null
python3 - "$WORLDLINE_SOCKET" <<'PY'
import json,socket,sys
path=sys.argv[1]
def rpc(op,args=None,version=1):
    with socket.socket(socket.AF_UNIX) as s:
        s.connect(path)
        s.sendall((json.dumps({'protocol':version,'op':op,'args':args or {}})+'\n').encode())
        return json.loads(s.makefile().readline())
old=rpc('event',{'key':'task.done','value':True},99)
assert old['error']['code']=='protocol_mismatch'
baseline=rpc('fence')['result']['revision']
rpc('event',{'event':{'source':'atspi','facts':{'ui.focus.name':'Editor'}}})
ready=rpc('wait',{'after_revision':baseline,'predicates':[{'path':'ui.focus.name','op':'eq','value':'Editor','fresh_after':baseline}]})
assert ready['result']['code']=='ready'
stale=rpc('wait',{'after_revision':ready['result']['revision'],'predicates':[{'path':'ui.focus.name','op':'eq','value':'Editor','fresh_after':ready['result']['revision']}]})
assert stale['result']['code']=='pending'
rpc('event',{'event':{'source':'atspi','facts':{'ui.focus.name':'Other'}}})
conflict=rpc('wait',{'after_revision':ready['result']['revision'],'predicates':[{'path':'never','op':'exists'}],'conflict_paths':['ui.focus']})
assert conflict['result']['code']=='conflict'
receipt=rpc('receipt',{'owner':'cua','action_id':'sample','before_revision':baseline,'action_ok':False,'predicate':{'path':'ui.focus.name','op':'eq','value':'Other'}})['result']
assert receipt['outcome']=='failed' and receipt['revision_domain']=='worldline'
print('ok - one socket rejects skew and preserves causal revisions')
PY
python3 "$ROOT/scripts/worldline.py" request --json '{"op":"status"}' >"$TMP/status.json"
python3 - "$TMP/status.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert d['ok'] and isinstance(d['revision'],int)
PY
printf 'ok - GWCU client reads standalone WORLDLINE\n'
