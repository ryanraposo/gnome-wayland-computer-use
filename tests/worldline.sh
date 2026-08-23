#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }
world="$ROOT/scripts/worldline.py"

python3 -m py_compile "$world" || fail "WORLDLINE parses"
XDG_RUNTIME_DIR="$TMP/self" python3 "$world" self-test >"$TMP/self.json"
python3 - "$TMP/self.json" <<'PY' || fail "WORLDLINE self-test envelope"
import json,sys
d=json.load(open(sys.argv[1])); assert d["schema"]=="gwcu.worldline.v1" and d["ok"] and d["code"]=="self_test_ok"
PY
pass "WORLDLINE reducer/wait self-test"

mkdir -p "$TMP/runtime"
XDG_RUNTIME_DIR="$TMP/runtime" GWCU_WORLDLINE_IDLE_SECONDS=30 python3 "$world" serve >"$TMP/server.out" 2>"$TMP/server.err" &
pid=$!
for _ in $(seq 1 50); do [ -S "$TMP/runtime/gnome-wayland-computer-use/worldline.sock" ] && break; sleep .02; done
[ -S "$TMP/runtime/gnome-wayland-computer-use/worldline.sock" ] || fail "WORLDLINE private socket appeared"

XDG_RUNTIME_DIR="$TMP/runtime" python3 "$world" request --json '{"op":"wait","timeout_ms":2000,"predicates":[{"id":"done","path":"task.download.done","op":"eq","value":true}]}' >"$TMP/wait.json" &
waiter=$!
sleep .05
XDG_RUNTIME_DIR="$TMP/runtime" python3 "$world" request --json '{"op":"event","event":{"source":"task","type":"download-complete","facts":{"task.download.done":true},"invalidates":["ui.semantic"]}}' >"$TMP/event.json"
wait "$waiter"

python3 - "$TMP/event.json" "$TMP/wait.json" <<'PY' || fail "event-driven wake invalid"
import json,sys
e=json.load(open(sys.argv[1])); w=json.load(open(sys.argv[2]))
assert e["ok"] and e["code"]=="applied" and e["revision"]>=1
assert w["ok"] and w["code"]=="ready" and "done" in w["predicates"]
assert w["revision"]>=e["revision"]
PY
pass "event ingestion advances WORLDLINE and wakes a blocking predicate wait"

XDG_RUNTIME_DIR="$TMP/runtime" python3 "$world" request --json '{"op":"wait","timeout_ms":50,"branches":[{"id":"downloaded","predicates":[{"path":"task.download.done","op":"eq","value":true}]},{"id":"dialog","predicates":[{"path":"ui.dialog.name","op":"exists"}]}]}' >"$TMP/branch.json"
python3 - "$TMP/branch.json" <<'PY' || fail "branch selection invalid"
import json,sys
d=json.load(open(sys.argv[1])); assert d["ok"] and d["matched_branch"]=="downloaded"
PY
pass "WORLDLINE resolves predetermined branches locally"

XDG_RUNTIME_DIR="$TMP/runtime" python3 "$world" request --json '{"op":"close"}' >/dev/null || true
wait "$pid" || true

grep -q 'WORLDLINE never injects input' "$world" || fail "WORLDLINE authority boundary missing"
! grep -Eq 'ydotool|/dev/uinput|uinput' "$world" || fail "WORLDLINE contains raw input path"
grep -q 'op=="wait"' "$world" || fail "WORLDLINE wait operation missing"
grep -q 'Thread(target=client' "$world" || fail "WORLDLINE server cannot ingest events while waiting"
pass "WORLDLINE remains read-only while owning contingent continuation"
