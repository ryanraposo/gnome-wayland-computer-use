#!/usr/bin/env bash
# Hermes integration checks: the installed skill owns /computer-use; the plugin
# may replace the built-in computer_use TOOL only through Hermes' consented
# tools.override capability.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

build_bundle() {
    local dst=$1
    rm -rf "$dst"; mkdir -p "$dst"
    for f in VERSION README.md SKILL.md; do cp "$ROOT/$f" "$dst/$f"; done
    for d in scripts systemd agents; do [ -d "$ROOT/$d" ] && cp -a "$ROOT/$d" "$dst/"; done
    chmod +x "$dst/scripts"/*.sh "$dst/scripts"/*.py
}

make_home() {
    local home=$1 plugin_dir
    mkdir -p "$home/plugins" "$home/skills"
    plugin_dir="$home/plugins/gnome-wayland-computer-use"; mkdir -p "$plugin_dir"
    cp "$ROOT/runtimes/hermes/plugin.yaml" "$plugin_dir/plugin.yaml"
    cp "$ROOT/runtimes/hermes/__init__.py" "$plugin_dir/__init__.py"
    : >"$plugin_dir/.gnome-wayland-computer-use-managed"
    build_bundle "$home/skills/computer-use"
    : >"$home/skills/computer-use/.gnome-wayland-computer-use-managed"
    cat >"$home/config.yaml" <<'YAML'
plugins:
  enabled:
    - gnome-wayland-computer-use
YAML
}

# Source-level invariants always run, even on CI without Hermes installed.
! grep -Fq 'ctx.register_command(' "$ROOT/runtimes/hermes/__init__.py" || fail "plugin shadows native /computer-use"
grep -Fq '/computer-use <task>' "$ROOT/SKILL.md" || fail "skill-native task invocation missing"
grep -Fq 'Everything else is a task.' "$ROOT/SKILL.md" || fail "skill task/subcommand dispatch rule missing"
grep -Fq 'tools.override' "$ROOT/runtimes/hermes/plugin.yaml" || fail "Hermes tool override capability is undeclared"
! grep -Fq 'provides_tools:' "$ROOT/runtimes/hermes/plugin.yaml" || fail "conditional override is incorrectly advertised as an unconditional tool"
pass "skill owns slash routing while plugin declares only consented tool policy"

# Exercise the policy wrapper without depending on a Hermes installation. This
# catches the exact bug seen in the diagnostic: direct Hermes computer_use
# actions defaulted to background even when GWCU background priority was OFF.
python3 - "$ROOT/runtimes/hermes/__init__.py" "$TMP/policy-state" <<'PY' || fail "Hermes policy wrapper regression"
import importlib.util, os, pathlib, sys, types
plugin_path, state = sys.argv[1:]
os.environ['XDG_STATE_HOME'] = state
pathlib.Path(state).mkdir(parents=True, exist_ok=True)

schema_mod = types.ModuleType('tools.computer_use.schema')
schema_mod.COMPUTER_USE_SCHEMA = {'name':'computer_use','description':'builtin','parameters':{'type':'object'}}
tool_mod = types.ModuleType('tools.computer_use.tool')
seen=[]
def builtin(args, **kwargs):
    seen.append(dict(args)); return dict(args)
tool_mod.handle_computer_use = builtin
pkg_tools = types.ModuleType('tools'); pkg_cu = types.ModuleType('tools.computer_use')
sys.modules['tools'] = pkg_tools; sys.modules['tools.computer_use'] = pkg_cu
sys.modules['tools.computer_use.schema'] = schema_mod; sys.modules['tools.computer_use.tool'] = tool_mod

spec=importlib.util.spec_from_file_location('gwcu_hermes_policy', plugin_path)
mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
class Ctx:
    def __init__(self, allowed=True): self.allowed=allowed; self.registration=None
    def has_capability(self, name): return self.allowed and name == 'tools.override'
    def register_tool(self, **kwargs): self.registration=kwargs
ctx=Ctx(); mod.register(ctx)
assert ctx.registration is not None and ctx.registration['name']=='computer_use'
assert ctx.registration['override'] is True
wrapped=ctx.registration['handler']

# Default/OFF => foreground, mechanically.
out=wrapped({'action':'click','coordinate':[1,2]})
assert out['delivery_mode']=='foreground'
# Saved ON => background.
pref=pathlib.Path(state)/'gnome-wayland-computer-use'/'background-priority'; pref.parent.mkdir(parents=True, exist_ok=True); pref.write_text('on\n')
out=wrapped({'action':'key','keys':'ctrl+l'})
assert out['delivery_mode']=='background'
# Explicit call intent always survives the shim.
out=wrapped({'action':'click','delivery_mode':'foreground'})
assert out['delivery_mode']=='foreground'
# Reads and Cua typed-browser actions do not gain unsupported delivery args.
assert 'delivery_mode' not in wrapped({'action':'capture'})
assert 'delivery_mode' not in wrapped({'action':'cua_browser_click','ref':'x'})
# Capability denial fails closed: no override registration.
ctx2=Ctx(False); mod.register(ctx2); assert ctx2.registration is None
PY
pass "Hermes computer_use mechanically honors GWCU standing delivery preference"

HOME_A="$TMP/hermes-a"
make_home "$HOME_A"
[ -f "$HOME_A/skills/computer-use/SKILL.md" ] || fail "Hermes skill bundle missing"
[ -f "$HOME_A/skills/computer-use/README.md" ] || fail "single installed README missing"
for retired in WORLDLINE.md GWCU.md DETERMINISM.md CAPABILITIES.md PERF_NOTES.md references; do [ ! -e "$HOME_A/skills/computer-use/$retired" ] || fail "retired docs leaked into bundle: $retired"; done
pass "Hermes bundle carries runtime contract plus one README"

HERMES_PY=""
for c in "$HOME/.hermes/hermes-agent/venv/bin/python" "$HOME/.hermes/hermes-agent/venv/bin/python3"; do
    [ -x "$c" ] && HERMES_PY="$c" && break
done
if [ -z "$HERMES_PY" ]; then
    printf 'ok - Hermes runtime not present; skipping live registry integration checks\n'
    exit 0
fi
AGENT_DIR="$(cd "$(dirname "$HERMES_PY")/../.." && pwd)"
[ -d "$AGENT_DIR/hermes_cli" ] || fail "hermes_cli package missing at $AGENT_DIR"

run_hermes() {
    local home=$1 code=$2
    HERMES_HOME="$home" XDG_STATE_HOME="$TMP/state" PYTHONPATH="$AGENT_DIR" "$HERMES_PY" -c "$code"
}

# No plugin-level slash command: the installed skill remains canonical.
REGISTRY_CODE='from hermes_cli.plugins import get_plugin_commands
cmds = get_plugin_commands()
print("PLUGIN_HAS_COMPUTER_USE", "computer-use" in cmds)
'
OUT=$(run_hermes "$HOME_A" "$REGISTRY_CODE")
printf '%s\n' "$OUT" | grep -Fq 'PLUGIN_HAS_COMPUTER_USE False' || fail "plugin owns /computer-use"
pass "Hermes plugin registry leaves /computer-use to the skill"

# A stale older GWCU plugin can shadow the native skill path. Prove the upgrade
# retirement seam removes exactly that duplicate command owner.
HOME_B="$TMP/hermes-b"
make_home "$HOME_B"
mkdir -p "$HOME_B/plugins/zz-stale-computer-use"
cp "$ROOT/runtimes/hermes/plugin.yaml" "$HOME_B/plugins/zz-stale-computer-use/plugin.yaml"
printf '%s\n' 'def _run(raw_args): return "STALE"' \
    'def register(ctx): ctx.register_command("computer-use", _run, description="stale", args_hint="")' \
    >"$HOME_B/plugins/zz-stale-computer-use/__init__.py"
OUT=$(run_hermes "$HOME_B" "$REGISTRY_CODE")
printf '%s\n' "$OUT" | grep -Fq 'PLUGIN_HAS_COMPUTER_USE True' || fail "test setup: stale plugin did not shadow native skill path"

retire_duplicate_plugins() {
    local canonical=$1 dir name yaml
    for yaml in "$HOME_B/plugins"/*/plugin.yaml; do
        [ -f "$yaml" ] || continue
        name=$(awk -F': *' '/^name:[[:space:]]*/{gsub(/^[[:space:]]+|[[:space:]]+$|["'\'']/,"",$2); print $2; exit}' "$yaml")
        [ "$name" = "gnome-wayland-computer-use" ] || continue
        dir=$(dirname "$yaml"); [ "$dir" != "$canonical" ] || continue
        rm -rf "$dir"
    done
}
retire_duplicate_plugins "$HOME_B/plugins/gnome-wayland-computer-use"
OUT=$(run_hermes "$HOME_B" "$REGISTRY_CODE")
printf '%s\n' "$OUT" | grep -Fq 'PLUGIN_HAS_COMPUTER_USE False' || fail "stale plugin still shadows native skill path after retirement"
pass "duplicate retirement restores skill-native /computer-use ownership"

# Installer/teardown must preserve the upgrade seam and invoke Hermes enable,
# which is the host-owned capability-consent path for tools.override.
grep -Fq 'retire_duplicate_plugins' "$ROOT/install.sh" || fail "installer does not retire duplicate plugins"
grep -Fq '"$HERMES_HOME/plugins"/*/plugin.yaml' "$ROOT/install.sh" || fail "installer cannot scan plugin copies"
grep -Fq '"$HERMES_HOME/plugins"/*/plugin.yaml' "$ROOT/scripts/teardown.sh" || fail "teardown cannot find plugin copies"
grep -Fq 'hermes plugins enable "$NAME"' "$ROOT/install.sh" || fail "installer does not run Hermes capability-enable surface"
grep -Fq 'archived and restored by teardown' "$ROOT/install.sh" || fail "installer does not surface teardown-ability"
pass "installer/teardown keep clean slash ownership and consent seams"
