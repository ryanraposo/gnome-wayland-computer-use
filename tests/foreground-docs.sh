#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

python3 - "$ROOT" <<'PY'
import ast
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
policy = root / "runtimes/hermes/__init__.py"
skill = (root / "SKILL.md").read_text()
readme = (root / "README.md").read_text()
span = (root / "scripts/action-span.py").read_text()

# SKILL.md is the canonical agent contract. Derive the direct-Hermes foreground
# action set from the policy itself so that contract cannot silently omit a
# newly-added native input action.
tree = ast.parse(policy.read_text())
input_actions = None
for node in tree.body:
    if isinstance(node, ast.Assign):
        for target in node.targets:
            if isinstance(target, ast.Name) and target.id == "_INPUT_ACTIONS":
                call = node.value
                assert isinstance(call, ast.Call) and isinstance(call.func, ast.Name) and call.func.id == "frozenset"
                input_actions = set(ast.literal_eval(call.args[0]))
                break
    if input_actions is not None:
        break
assert input_actions, "Hermes _INPUT_ACTIONS missing"

assert "Foreground action coverage" in skill, "SKILL.md lacks foreground action coverage"
missing = sorted(action for action in input_actions if f"`{action}`" not in skill)
assert not missing, f"SKILL.md omits native foreground actions: {missing}"
for token in (
    "`launch_app`",
    "`focus_app`",
    "`set_value`",
    "`cua_browser_state`",
    "`cua_browser_*`",
    "`delivery_mode`",
    "exact `(pid, window_id)`",
):
    assert token in skill, f"SKILL.md lacks foreground-adjacent contract: {token}"

# README stays high-level and points at the skill rather than duplicating the
# action matrix. It must make the component boundary unambiguous.
for token in (
    "`SKILL.md` is the canonical agent contract",
    "Cua Driver's MCP/tool surface",
    "GWCU itself is not another MCP server",
    "Hermes policy plugin",
    "GWCU local runtime",
    "WORLDLINE",
    "`.gwcu`",
):
    assert token in readme, f"README lacks high-level component contract: {token}"
assert "Detailed agent behavior belongs in `SKILL.md`" in readme
assert "The exhaustive foreground action matrix belongs in `SKILL.md`" in readme

# Spans deliberately discover delivery capability from Cua's runtime schema.
assert '"delivery_mode" in props' in span, "action-span no longer discovers delivery-mode tools"
assert "every tool exposing `delivery_mode`" in skill, "skill no longer documents dynamic span coverage"
assert "every Cua tool exposing `delivery_mode`" in readme, "README no longer summarizes dynamic span coverage"

# Runtime skill mirror remains byte-identical to the canonical skill.
assert (root / "runtimes/openai/SKILL.md").read_bytes() == (root / "SKILL.md").read_bytes(), "runtime skill mirror drifted"

print("ok - exhaustive foreground contract lives in skill; README stays architectural")
PY
