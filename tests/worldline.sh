#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

world="$ROOT/scripts/worldline.py"
capture="$ROOT/scripts/worldline-capture.sh"

python3 -m py_compile "$world" || fail "WORLDLINE parses"
XDG_RUNTIME_DIR="$TMP/self" python3 "$world" self-test >"$TMP/self.json"
python3 - "$TMP/self.json" <<'PY' || fail "WORLDLINE self-test envelope"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["schema"]=="gwcu.worldline.v1" and d["ok"] and d["code"]=="self_test_ok"
PY
pass "WORLDLINE reducer self-test"

mkdir -p "$TMP/runtime"
XDG_RUNTIME_DIR="$TMP/runtime" GWCU_WORLDLINE_IDLE_SECONDS=30 python3 "$world" serve >"$TMP/server.out" 2>"$TMP/server.err" &
pid=$!
for _ in $(seq 1 50); do
    [ -S "$TMP/runtime/gnome-wayland-computer-use/worldline.sock" ] && break
    sleep .02
done
[ -S "$TMP/runtime/gnome-wayland-computer-use/worldline.sock" ] || fail "WORLDLINE private socket appeared"

XDG_RUNTIME_DIR="$TMP/runtime" python3 "$world" request --json '{
  "op":"arm",
  "id":"download",
  "mode":"all",
  "predicates":[{"path":"task.download.done","op":"eq","value":true}]
}' >/dev/null

XDG_RUNTIME_DIR="$TMP/runtime" python3 "$world" request --json '{
  "op":"event",
  "event":{
    "source":"task",
    "type":"download-complete",
    "facts":{"task.download.done":true,"ui.focus.name":"Browser"},
    "invalidates":["ui.semantic"]
  }
}' >/dev/null

XDG_RUNTIME_DIR="$TMP/runtime" "$capture" \
    --trigger task:download \
    --expect-json '[{"id":"done","path":"task.download.done","op":"eq","value":true}]' \
    >"$TMP/revision.json"

python3 - "$TMP/revision.json" <<'PY' || fail "revision contract invalid"
import json,sys
d=json.load(open(sys.argv[1]))
assert d["schema"]=="gwcu.worldline.revision.v1"
assert d["ok"] and d["revision"]==1
assert "task.download.done" in d["changed"]
assert "ui.semantic" in d["invalidated"]
assert "done" in d["predicates_satisfied"]
assert "download" in d["woken"]
assert d["events"]["sources"]["task"]==1
PY
pass "events become revisions and wake predicates"

XDG_RUNTIME_DIR="$TMP/runtime" python3 "$world" request --json '{"op":"close"}' >/dev/null || true
wait "$pid" || true

grep -q 'WORLDLINE never injects input' "$world" || fail "WORLDLINE authority boundary missing"
! grep -Eq 'ydotool|/dev/uinput|uinput' "$world" || fail "WORLDLINE contains raw input path"
grep -q 'observer_capture' "$world" || fail "WORLDLINE lost visual escalation hook"
grep -q 'Atspi.EventListener' "$world" || fail "WORLDLINE lost AT-SPI event adapter"
grep -qi 'valid until invalidated' "$ROOT/WORLDLINE.md" || fail "WORLDLINE docs lost invalidation model"
pass "WORLDLINE stays read-only and event-driven"
