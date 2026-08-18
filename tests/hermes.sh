#!/usr/bin/env bash
# Natural Hermes integration tests: drive the /computer-use plugin through
# Hermes' own plugin registry against a sandboxed HERMES_HOME, and prove that
# a stale duplicate plugin no longer shadows the project's command.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ printf 'not ok - %s\n' "$1" >&2; exit 1; }
pass(){ printf 'ok - %s\n' "$1"; }

HERMES_PY=""
for c in "$HOME/.hermes/hermes-agent/venv/bin/python" "$HOME/.hermes/hermes-agent/venv/bin/python3"; do
    [ -x "$c" ] && HERMES_PY="$c" && break
done
if [ -z "$HERMES_PY" ]; then
    printf 'ok - Hermes runtime not present; skipping hermes-native integration tests\n'
    exit 0
fi
AGENT_DIR="$(cd "$(dirname "$HERMES_PY")/../.." && pwd)"
[ -d "$AGENT_DIR/hermes_cli" ] || fail "hermes_cli package missing at $AGENT_DIR"

# Build the same payload install.sh ships: root docs + scripts + systemd units.
build_bundle() {
    local dst=$1
    rm -rf "$dst"; mkdir -p "$dst"
    for f in VERSION README.md WORLDLINE.md GWCU.md DETERMINISM.md CAPABILITIES.md PERF_NOTES.md SKILL.md; do
        [ -f "$ROOT/$f" ] && cp "$ROOT/$f" "$dst/$f"
    done
    for d in scripts systemd agents references; do
        [ -d "$ROOT/$d" ] && cp -a "$ROOT/$d" "$dst/"
    done
    chmod +x "$dst/scripts"/*.sh "$dst/scripts"/*.py
}

# Layout a sandboxed HERMES_HOME the way install.sh does for the Hermes branch.
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

# Run one Python snippet through Hermes' plugin registry in a sandboxed home.
run_hermes() {
    local home=$1 code=$2
    HERMES_HOME="$home" XDG_STATE_HOME="$TMP/state" PYTHONPATH="$AGENT_DIR" \
        "$HERMES_PY" -c "$code"
}

REGISTER_CODE='import json
from hermes_cli.plugins import get_plugin_commands, get_plugin_command_handler
cmds = get_plugin_commands()
info = cmds.get("computer-use", {})
print(json.dumps({"keys": sorted(cmds), "owner": info.get("plugin"), "desc": info.get("description")}))
h = get_plugin_command_handler("computer-use")
print("HELP_HAS_BACKGROUND", "background [on|off|status]" in (h("help") or ""))
print("BG", (h("background status") or "").splitlines()[0])
'

HOME_A="$TMP/hermes-a"
make_home "$HOME_A"
OUT=$(run_hermes "$HOME_A" "$REGISTER_CODE")
printf '%s\n' "$OUT"
echo "$OUT" | python3 -c '
import json,sys
data = {}
for line in sys.stdin:
    if line.startswith("{"):
        data = json.loads(line)
    elif line.startswith("HELP_HAS_BACKGROUND"):
        data["help_bg"] = line.strip().split(" ",1)[1]
    elif line.startswith("BG "):
        data["bg"] = line.strip().split(" ",1)[1]
assert data.get("keys") == ["computer-use"], data
assert data.get("owner") == "gnome-wayland-computer-use", data
assert data.get("help_bg") == "True", data
assert data.get("bg") == "Background computer use: OFF", data
' || fail "registered /computer-use does not dispatch the project backend"
pass "/computer-use registers and dispatches through Hermes' plugin registry"

# A stale duplicate plugin with the same plugin.yaml name but a directory that
# sorts AFTER the canonical one shadows /computer-use. The installer's
# retire_duplicate_plugins must remove it so the project's command wins.
STALE_CODE='from hermes_cli.plugins import get_plugin_command_handler
print((get_plugin_command_handler("computer-use")("") or ""))'
HOME_B="$TMP/hermes-b"
make_home "$HOME_B"
mkdir -p "$HOME_B/plugins/zz-stale-computer-use"
cp "$ROOT/runtimes/hermes/plugin.yaml" "$HOME_B/plugins/zz-stale-computer-use/plugin.yaml"
printf '%s\n' '"""stale pre-replacement plugin."""' \
    'def _run(raw_args): return "STALE /computer-use: not replaced"' \
    'def register(ctx): ctx.register_command("computer-use", _run, description="stale", args_hint="")' \
    >"$HOME_B/plugins/zz-stale-computer-use/__init__.py"
OUT=$(run_hermes "$HOME_B" "$STALE_CODE")
printf '%s\n' "$OUT" | grep -Fq 'STALE /computer-use: not replaced' || fail "test setup: stale duplicate did not shadow /computer-use"
pass "stale duplicate plugin shadows /computer-use before retirement"

# Replicate install.sh's retire_duplicate_plugins contract against the sandbox.
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
[ ! -e "$HOME_B/plugins/zz-stale-computer-use" ] || fail "stale duplicate plugin was not retired"
OUT=$(run_hermes "$HOME_B" "$STALE_CODE")
printf '%s\n' "$OUT" | grep -Fq '/computer-use commands' || fail "project /computer-use did not win after retirement"
printf '%s\n' "$OUT" | grep -Fq 'STALE /computer-use' && fail "stale command survived retirement"
pass "retiring duplicate plugins replaces /computer-use with the project command"

# A missing Hermes skill copy must fall back to the agent skill backend.
AGENT_HOME="$TMP/hermes-home-agent"
HOME_C="$TMP/hermes-c"
make_home "$HOME_C"
rm -rf "$HOME_C/skills/computer-use"
mkdir -p "$AGENT_HOME/.agents/skills/gnome-wayland-computer-use"
build_bundle "$AGENT_HOME/.agents/skills/gnome-wayland-computer-use"
OUT=$(HOME="$AGENT_HOME" HERMES_HOME="$HOME_C" XDG_STATE_HOME="$TMP/state" PYTHONPATH="$AGENT_DIR" \
    "$HERMES_PY" -c "$STALE_CODE")
printf '%s\n' "$OUT" | grep -Fq '/computer-use commands' || fail "backend fallback to agent skill copy failed"
pass "Hermes backend falls back to the agent skill copy when the Hermes skill is missing"

# The installer and teardown must carry the duplicate-plugin retirement seam.
grep -Fq 'retire_duplicate_plugins' "$ROOT/install.sh" || fail "installer does not retire duplicate plugins"
grep -Fq '"$HERMES_HOME/plugins"/*/plugin.yaml' "$ROOT/install.sh" || fail "installer cannot scan plugin copies"
grep -Fq '"$HERMES_HOME/plugins"/*/plugin.yaml' "$ROOT/scripts/teardown.sh" || fail "teardown cannot find plugin copies"
grep -Fq 'hermes plugins enable "$NAME"' "$ROOT/install.sh" || fail "installer does not enable the plugin"
grep -Fq 'archived and restored by teardown' "$ROOT/install.sh" || fail "installer does not surface teardown-ability"
pass "installer/teardown keep /computer-use replacement seams"
