#!/usr/bin/env bash
# Hermes integration checks: skill task dispatch + completion enrichment +
# mechanically enforced exact foreground presentation and ACQUIRE.
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
  entries:
    gnome-wayland-computer-use:
      allow_tool_override: true
      granted_capabilities: [tools.override]
YAML
}

! grep -Fq 'ctx.register_command(' "$ROOT/runtimes/hermes/__init__.py" || fail "plugin shadows skill task dispatch"
grep -Fq '/computer-use <task>' "$ROOT/SKILL.md" || fail "skill-native task invocation missing"
grep -Fq 'Everything else is a task.' "$ROOT/SKILL.md" || fail "skill task/subcommand dispatch rule missing"
grep -Fq 'tools.override' "$ROOT/runtimes/hermes/plugin.yaml" || fail "Hermes tool override capability is undeclared"
! grep -Fq 'provides_tools:' "$ROOT/runtimes/hermes/plugin.yaml" || fail "conditional override is advertised as unconditional"
grep -Fq '"launch_app"' "$ROOT/runtimes/hermes/__init__.py" || fail "Hermes computer_use does not expose ACQUIRE"
grep -Fq 'new_window_ambiguous' "$ROOT/runtimes/hermes/__init__.py" || fail "ACQUIRE does not fail closed on ambiguity"
pass "skill owns task dispatch while plugin declares one policy capability"

cat >"$TMP/presenter.py" <<'PY'
#!/usr/bin/env python3
import json,os,pathlib,sys
if os.environ.get('PRESENT_LOG'):pathlib.Path(os.environ['PRESENT_LOG']).open('a').write(' '.join(sys.argv[1:])+'\n')
ok=os.environ.get('PRESENT_FAIL')!='1'
print(json.dumps({'schema':'gwcu.presentation.v1','ok':ok,'code':'presented' if ok else 'focus_not_proved'}))
raise SystemExit(0 if ok else 30)
PY
chmod +x "$TMP/presenter.py"
cat >"$TMP/resolver.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"schema":"gwcu.identity.v1","ok":true,"code":"resolved","result":{"display_name":"Calculator","desktop_id":"org.gnome.Calculator.desktop","app_id":"org.gnome.Calculator","kind":"native-app","exec":"gnome-calculator"}}'
SH
chmod +x "$TMP/resolver.sh"

python3 - "$ROOT/runtimes/hermes/__init__.py" "$TMP/state" "$TMP/presenter.py" "$TMP/present.log" "$TMP/resolver.sh" <<'PY' || fail "Hermes policy/completion/ACQUIRE regression"
import importlib.util, json, os, pathlib, sys, types
plugin_path,state,presenter,present_log,resolver=sys.argv[1:]
os.environ['XDG_STATE_HOME']=state
os.environ['GWCU_PRESENTER']=presenter
os.environ['GWCU_APP_RESOLVER']=resolver
os.environ['PRESENT_LOG']=present_log
pathlib.Path(state).mkdir(parents=True,exist_ok=True)

# Fake built-in computer_use surface plus one Cua backend session.
schema_mod=types.ModuleType('tools.computer_use.schema')
schema_mod.COMPUTER_USE_SCHEMA={'name':'computer_use','description':'builtin','parameters':{'type':'object'}}
tool_mod=types.ModuleType('tools.computer_use.tool')
seen=[]
def builtin(args,**kwargs):seen.append(dict(args));return dict(args)
tool_mod.handle_computer_use=builtin
class Backend:
    def __init__(self):self.launched=False;self.launch_names=[]
    def list_windows(self):
        return [{'pid':4242,'window_id':77,'title':'Calculator'}] if self.launched else []
    def launch_app(self,**kwargs):
        self.launch_names.append(kwargs.get('name'));self.launched=True
        return {'pid':4242,'name':'Calculator','windows':[]}
backend=Backend()
tool_mod._get_backend=lambda session_id: backend
tool_mod._request_approval=lambda scope,args: None
sys.modules['tools']=types.ModuleType('tools')
sys.modules['tools.computer_use']=types.ModuleType('tools.computer_use')
sys.modules['tools.computer_use.schema']=schema_mod
sys.modules['tools.computer_use.tool']=tool_mod

# Fake Hermes command completer contract.
commands=types.ModuleType('hermes_cli.commands');commands.SUBCOMMANDS={}
class Completer:
    def _normalize_skill_token(self,token):return token.lower()
    def _is_skill_command(self,token):return token in {'/computer-use','/other-skill'}
commands.SlashCommandCompleter=Completer
hermes=types.ModuleType('hermes_cli');hermes.commands=commands
sys.modules['hermes_cli']=hermes;sys.modules['hermes_cli.commands']=commands

spec=importlib.util.spec_from_file_location('gwcu_hermes_policy',plugin_path)
mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
class Ctx:
    def __init__(self,allowed=True):self.allowed=allowed;self.registration=None;self.cleanups=[]
    def has_capability(self,name):return self.allowed and name=='tools.override'
    def register_tool(self,**kwargs):self.registration=kwargs
    def on_unload(self,fn):self.cleanups.append(fn)

ctx=Ctx();mod.register(ctx)
assert ctx.registration and ctx.registration['name']=='computer_use' and ctx.registration['override'] is True
assert 'launch_app' in ctx.registration['schema']['parameters']['properties']['action']['enum']
assert commands.SUBCOMMANDS['/computer-use']==list(mod._SUBCOMMANDS)
c=Completer();assert c._is_skill_command('/computer-use') is False;assert c._is_skill_command('/other-skill') is True
wrapped=ctx.registration['handler']

# ACQUIRE is resolved locally, launched through Cua, and returns one exact NEW target.
raw=wrapped({'action':'launch_app','app':'Calculator'},session_id='cold')
acq=json.loads(raw)
assert acq['ok'] is True and acq['phase']=='ACQUIRE' and acq['target']=={'pid':4242,'window_id':77}
assert backend.launch_names==['Calculator'] and len(seen)==0

# OFF/default = exact foreground presentation BEFORE builtin actuation.
out=wrapped({'action':'click','pid':123,'window_id':9,'coordinate':[1,2]})
assert out['delivery_mode']=='foreground';assert seen[-1]['pid']==123 and seen[-1]['window_id']==9
assert pathlib.Path(present_log).read_text().count('present --pid 123 --window-id 9')==1

# Missing exact identity fails before the built-in handler sees anything.
before=len(seen)
try:wrapped({'action':'click','coordinate':[1,2]})
except RuntimeError as exc:assert 'exact_target_required_for_foreground' in str(exc)
else:raise AssertionError('targetless foreground did not fail')
assert len(seen)==before

# Presentation refusal also fails pre-actuation.
os.environ['PRESENT_FAIL']='1';before=len(seen)
try:wrapped({'action':'click','pid':123,'window_id':9,'coordinate':[1,2]})
except RuntimeError as exc:assert 'focus_not_proved' in str(exc)
else:raise AssertionError('failed presentation did not fail')
assert len(seen)==before
os.environ.pop('PRESENT_FAIL')

# Saved ON = background; no presentation gate for ordinary work.
pref=pathlib.Path(state)/'gnome-wayland-computer-use'/'background-priority';pref.parent.mkdir(parents=True,exist_ok=True);pref.write_text('on\n')
present_before=pathlib.Path(present_log).read_text()
out=wrapped({'action':'key','pid':123,'window_id':9,'keys':'ctrl+l'})
assert out['delivery_mode']=='background';assert pathlib.Path(present_log).read_text()==present_before

# Reads and typed-browser actions do not gain unsupported delivery args.
assert 'delivery_mode' not in wrapped({'action':'capture'})
assert 'delivery_mode' not in wrapped({'action':'cua_browser_click','ref':'x'})

# Modern capability denial fails closed for tool override but completion remains.
ctx2=Ctx(False);mod.register(ctx2);assert ctx2.registration is None
assert commands.SUBCOMMANDS['/computer-use']==list(mod._SUBCOMMANDS)

# Pre-capability Hermes: explicit plugin enable was the host trust boundary.
class LegacyCtx:
    def __init__(self):self.registration=None
    def register_tool(self,**kwargs):self.registration=kwargs
legacy=LegacyCtx();mod.register(legacy);assert legacy.registration and legacy.registration['override'] is True
PY
pass "Hermes ACQUIRE launches through Cua, binds exact new window, and foreground input stays exact/presented"

HOME_A="$TMP/hermes-a";make_home "$HOME_A"
[ -f "$HOME_A/skills/computer-use/SKILL.md" ] || fail "Hermes skill bundle missing"
[ -f "$HOME_A/skills/computer-use/scripts/present-window.py" ] || fail "presentation gate missing from Hermes skill bundle"
for retired in WORLDLINE.md GWCU.md DETERMINISM.md CAPABILITIES.md PERF_NOTES.md references; do [ ! -e "$HOME_A/skills/computer-use/$retired" ] || fail "retired docs leaked into bundle: $retired"; done
pass "Hermes bundle carries skill, presenter and one README"

# Installer owns exact automatic plugin enablement, not a post-install chore.
grep -Fq 'hermes_exec config set plugins.enabled' "$ROOT/install.sh" || fail "installer does not enable GWCU in Hermes config"
grep -Fq 'hermes_exec config set plugins.disabled' "$ROOT/install.sh" || fail "installer does not clear stale GWCU disable"
grep -Fq 'plugins.entries.$APP_ID.granted_capabilities' "$ROOT/install.sh" || fail "tools.override grant not installed"
grep -Fq 'plugins.entries.$APP_ID.allow_tool_override' "$ROOT/install.sh" || fail "legacy tool override bridge not installed"
grep -Fq 'Hermes plugin enabled; computer_use policy is mechanical' "$ROOT/install.sh" || fail "installer does not verify enabled policy"
! grep -Fq 'enable it later' "$ROOT/install.sh" || fail "installer still delegates plugin activation to user"
pass "installer enables the exact Hermes policy automatically"

# When a local Hermes source checkout is available, verify there is no plugin
# slash command collision: /computer-use remains a native skill invocation.
HERMES_PY=""
for c in "$HOME/.hermes/hermes-agent/venv/bin/python" "$HOME/.hermes/hermes-agent/venv/bin/python3"; do [ -x "$c" ] && HERMES_PY="$c" && break; done
if [ -z "$HERMES_PY" ]; then
    printf 'ok - Hermes runtime not present; skipping live registry integration check\n'
    exit 0
fi
AGENT_DIR="$(cd "$(dirname "$HERMES_PY")/../.." && pwd)"
[ -d "$AGENT_DIR/hermes_cli" ] || fail "hermes_cli package missing at $AGENT_DIR"
OUT=$(HERMES_HOME="$HOME_A" XDG_STATE_HOME="$TMP/state-live" PYTHONPATH="$AGENT_DIR" "$HERMES_PY" - <<'PY'
from hermes_cli.plugins import get_plugin_commands
print('PLUGIN_HAS_COMPUTER_USE', 'computer-use' in get_plugin_commands())
PY
)
printf '%s\n' "$OUT" | grep -Fq 'PLUGIN_HAS_COMPUTER_USE False' || fail "plugin stole /computer-use from the skill"
pass "live Hermes registry leaves task-form /computer-use to the skill"
