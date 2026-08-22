#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

skill_description() {
    awk 'NR==1&&$0=="---"{f=1;next} f&&$0=="---"{exit} f&&/^description:[[:space:]]*/{sub(/^description:[[:space:]]*/,"");print;exit}' "$1"
}

a=$(skill_description "$ROOT/SKILL.md")
b=$(skill_description "$ROOT/runtimes/openai/SKILL.md")
[ -n "$a" ] && [ "${#a}" -lt 60 ] || fail "Hermes description is compact"
[ "$a" = "$b" ] || fail "runtime descriptions differ"
cmp -s "$ROOT/SKILL.md" "$ROOT/runtimes/openai/SKILL.md" || fail "runtime skill payloads drifted"
pass "runtime skills are identical and compact"

for heading in \
    'Invocation contract' 'One actuator, including the browser' 'Core rule' 'Control priority' 'Visible-result contract' \
    'Call budget' 'Execution ladder' 'Known target' 'WORLDLINE postconditions' 'Whole screen' \
    '`.gwcu`: durable truth, not runtime state' 'Failure and refusal policy' 'Completion proof'
do
    grep -Fqi "## $heading" "$ROOT/SKILL.md" || fail "skill lost: $heading"
done
grep -Fq '/computer-use <task>' "$ROOT/SKILL.md" || fail "task-form slash invocation missing"
grep -Fq 'Everything else is a task.' "$ROOT/SKILL.md" || fail "task/subcommand dispatch rule missing"

python3 - "$ROOT" <<'PY' || fail "operator command documentation/completion drift"
import ast
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
surface = (root / "scripts/computer-use.sh").read_text()

# Four-space case arms are the top-level computer-use.sh dispatch. `span` is
# intentionally an internal composition surface, not a slash operator.
operators = []
for line in surface.splitlines():
    match = re.match(r"^    ([a-z][a-z0-9-]*)(?:\|[^)]*)?\)$", line)
    if match and match.group(1) != "span":
        operators.append(match.group(1))
assert operators, "no operator commands discovered from computer-use.sh"
assert len(operators) == len(set(operators)), f"duplicate operator dispatch arms: {operators}"

for relative in ("SKILL.md", "runtimes/openai/SKILL.md", "README.md"):
    text = (root / relative).read_text()
    missing = [name for name in operators if f"/computer-use {name}" not in text]
    assert not missing, f"{relative} missing operator docs: {missing}"

plugin_path = root / "runtimes/hermes/__init__.py"
tree = ast.parse(plugin_path.read_text())
subcommands = None
for node in tree.body:
    if isinstance(node, ast.Assign):
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id == "_SUBCOMMANDS":
                subcommands = list(ast.literal_eval(node.value))
                break
    if subcommands is not None:
        break
assert subcommands is not None, "Hermes _SUBCOMMANDS missing"
assert len(subcommands) == len(set(subcommands)), f"duplicate Hermes subcommands: {subcommands}"
assert set(subcommands) == set(operators), (
    f"operator/completion mismatch: dispatch={operators}, _SUBCOMMANDS={subcommands}"
)
assert "span" not in subcommands, "internal span leaked into slash completion"
assert "computer-use.sh span" in (root / "README.md").read_text(), "internal span distinction undocumented in README"
PY
pass "operator dispatch, docs and Hermes completion are locked together"

! grep -Fq 'ctx.register_command(' "$ROOT/runtimes/hermes/__init__.py" || fail "Hermes plugin shadows skill task dispatch"
grep -Fq 'installed skill owns ``/computer-use`` task dispatch' "$ROOT/runtimes/hermes/__init__.py" || fail "Hermes slash ownership contract missing"
grep -Fq 'SUBCOMMANDS["/computer-use"]' "$ROOT/runtimes/hermes/__init__.py" || fail "Hermes completion metadata missing"
grep -Fq 'normalized == "/computer-use"' "$ROOT/runtimes/hermes/__init__.py" || fail "skill-completer exception missing"
pass "/computer-use keeps task dispatch while reserved subcommands autocomplete"

grep -q 'MUST cross the model/tool boundary exactly once' "$ROOT/SKILL.md" || fail "one-call invariant softened"
grep -q 'computer-use.sh" span --actions-json' "$ROOT/SKILL.md" || fail "span surface missing"
grep -q 'worldline-capture.sh' "$ROOT/SKILL.md" || fail "WORLDLINE surface missing"
grep -q 'Never answer a Cua refusal with raw pointer/keyboard injection' "$ROOT/SKILL.md" || fail "refusal boundary missing"
grep -q 'No X11 or XWayland session is required' "$ROOT/SKILL.md" || fail "GNOME Wayland contract missing"
grep -q 'toggles the standing delivery preference' "$ROOT/SKILL.md" || fail "background command contract missing"
grep -q 'documentation lives in `README.md`' "$ROOT/SKILL.md" || fail "skill points at retired docs"
pass "skill teaches one Cua + WORLDLINE execution contract"

# Invisible-control regression constitution.
grep -Fq "do not route browser work through Hermes' separate \`browser_*\` toolset" "$ROOT/SKILL.md" || fail "browser actuator split can recur"
grep -Fq 'cua_browser_state / cua_browser_* actions' "$ROOT/SKILL.md" || fail "Cua browser route is not explicit"
grep -Fq 'binding_quality:"exact"' "$ROOT/SKILL.md" || fail "typed browser route no longer requires exact native binding"
grep -Fq 'mutation_allowed:true' "$ROOT/SKILL.md" || fail "typed browser mutation admission is incomplete"
grep -Fq 'Every mutation invalidates refs.' "$ROOT/SKILL.md" || fail "typed browser refs can silently go stale"
grep -Fq 'An unselected tab may still be fully addressable.' "$ROOT/SKILL.md" || fail "typed browser visibility trap is undocumented"
grep -Fq 'Firefox has no typed page-mutation route' "$ROOT/SKILL.md" || fail "Firefox can be misrouted into typed browser mutation"
grep -Fq 'A hidden/headless/managed browser success is a failure' "$ROOT/SKILL.md" || fail "visible-result failure is not explicit"
grep -Fqi 'There is deliberately **no floating confidence threshold**' "$ROOT/SKILL.md" || fail "confidence arbiter regression guard missing"
! grep -Eq 'F <|F >|0\.40|0\.60|\.40–\.60' "$ROOT/SKILL.md" || fail "obsolete confidence threshold still documented"
grep -Fq 'exact_pid_window -> cua_gnome_present -> focused_visible_proof -> cua_input' "$ROOT/scripts/action-span.py" || fail "action-span lost exact foreground invariant"
grep -Fq 'exact_target_required_for_foreground' "$ROOT/scripts/action-span.py" || fail "targetless foreground can recur"
grep -Fq 'presentation_not_proved' "$ROOT/scripts/action-span.py" || fail "presentation failure can leak into input"
grep -Fq 'tools.override' "$ROOT/runtimes/hermes/plugin.yaml" || fail "Hermes policy override is not declared"
pass "browser and exact foreground presentation are constitutionally covered"

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
SURFACE="$ROOT/scripts/computer-use.sh"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background status >"$TMP/default"
grep -q 'Background computer use: OFF' "$TMP/default" || fail "background default is not visible takeover"
grep -q 'EXACT VISIBLE TAKEOVER' "$TMP/default" || fail "default takeover contract missing"
XDG_STATE_HOME="$TMP/state" "$SURFACE" trace >"$TMP/trace"
for stage in DISCOVER PRESENT ACT REVALIDATE 'COMPLETE VISIBLY'; do grep -Fq "$stage" "$TMP/trace" || fail "trace lost stage: $stage"; done
grep -Fq 'otherwise STOP before input' "$ROOT/SKILL.md" || fail "pre-actuation failure boundary missing"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background >"$TMP/on"
grep -q 'Background computer use: ON' "$TMP/on" || fail "bare background command did not toggle on"
XDG_STATE_HOME="$TMP/state" "$SURFACE" background >"$TMP/off"
grep -q 'Background computer use: OFF' "$TMP/off" || fail "bare background command did not toggle off"
grep -q 'Default visible takeover is faster and deterministic' "$ROOT/install.sh" || fail "installer background choice missing"
pass "default control path is visible, pre-traced and deterministic"

# Machine-bound operator surfaces must be hermetic in CI.
mkdir -p "$TMP/bin"
cat >"$TMP/bin/cua-driver" <<'PY'
#!/usr/bin/env python3
import json, os, pathlib, sys
if len(sys.argv) < 2 or sys.argv[1] != "mcp":
    raise SystemExit(2)
for line in sys.stdin:
    msg = json.loads(line)
    method = msg.get("method")
    if method == "initialize":
        print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"protocolVersion":"2024-11-05","serverInfo":{"name":"cua-driver","version":"test"}}}), flush=True)
    elif method == "tools/call":
        args = msg.get("params", {}).get("arguments", {})
        log = os.environ.get("CUA_TEST_LOG")
        if log:
            pathlib.Path(log).open("a").write(json.dumps(args, separators=(",", ":")) + "\n")
        windows = [{"pid":4242,"window_id":77,"x":10,"y":20,"width":800,"height":600,"focused":True,"visible":True,"minimized":False,"z_index":0,"title":"CI Window"}]
        print(json.dumps({"jsonrpc":"2.0","id":msg["id"],"result":{"content":[],"isError":False,"structuredContent":{"windows":windows}}}), flush=True)
PY
cat >"$TMP/bin/gdbus" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"${GDBUS_TEST_LOG:?}"
printf '()\n'
SH
chmod +x "$TMP/bin/cua-driver" "$TMP/bin/gdbus"

CUA_TEST_LOG="$TMP/cua.log" CUA_DRIVER_BIN="$TMP/bin/cua-driver" XDG_STATE_HOME="$TMP/state" "$SURFACE" list-windows >"$TMP/list"
grep -q 'Found 1 windows:' "$TMP/list" || fail "list-windows did not parse Cua window list"
grep -q 'CI Window' "$TMP/list" || fail "list-windows table lost returned window"
CUA_TEST_LOG="$TMP/cua.log" CUA_DRIVER_BIN="$TMP/bin/cua-driver" XDG_STATE_HOME="$TMP/state" "$SURFACE" list-windows --on-screen-only --pid 4242 --json >"$TMP/list_on"
grep -q '"found": 1' "$TMP/list_on" || fail "list-windows --json lost returned window"
grep -q '"on_screen_only":true' "$TMP/cua.log" || fail "list-windows did not forward --on-screen-only"
grep -q '"pid":4242' "$TMP/cua.log" || fail "list-windows did not forward --pid"
if CUA_DRIVER_BIN="$TMP/bin/cua-driver" XDG_STATE_HOME="$TMP/state" "$SURFACE" list-windows --pid nope >/dev/null 2>&1; then fail "list-windows accepted invalid pid"; fi
PATH="$TMP/bin:$PATH" GDBUS_TEST_LOG="$TMP/gdbus.log" XDG_STATE_HOME="$TMP/state" "$SURFACE" cursor-color >"$TMP/cursor"
grep -q 'Set agent cursor color to #00FF00' "$TMP/cursor" || fail "cursor-color default green"
PATH="$TMP/bin:$PATH" GDBUS_TEST_LOG="$TMP/gdbus.log" XDG_STATE_HOME="$TMP/state" "$SURFACE" cursor-color "#FF0000" >"$TMP/cursor2"
grep -q 'Set agent cursor color to #FF0000' "$TMP/cursor2" || fail "cursor-color accepts custom hex"
grep -q '#FF0000' "$TMP/gdbus.log" || fail "cursor-color did not reach WinRects helper"
if PATH="$TMP/bin:$PATH" GDBUS_TEST_LOG="$TMP/gdbus.log" XDG_STATE_HOME="$TMP/state" "$SURFACE" cursor-color '#GG0000' >/dev/null 2>&1; then fail "cursor-color accepted invalid hex"; fi
pass "list-windows and cursor-color operator surfaces work hermetically"

grep -q '^## Maintaining this repository$' "$ROOT/AGENTS.md" || fail "repository guide lost maintenance routing"
grep -q 'Persistent machine/user truth never belongs in AGENTS.md' "$ROOT/AGENTS.md" || fail "AGENTS permits machine truth"
grep -q 'README.md.*only human-facing documentation file' "$ROOT/AGENTS.md" || fail "repository docs authority is unclear"
pass "repository/runtime/README authority remains separated"

version=$(tr -d '[:space:]' <"$ROOT/VERSION")
grep -q "^version: ${version}$" "$ROOT/SKILL.md" || fail "skill version mismatch"
[ "$version" = 2.3.0 ] || fail "release version is 2.3.0"
pass "version identity is consistent"
