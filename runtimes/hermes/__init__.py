"""Hermes integration for gnome-wayland-computer-use.

The installed skill owns ``/computer-use`` task dispatch. This plugin is enabled
by the installer and makes two policies mechanical instead of advisory:

* direct native ``computer_use`` input inherits GWCU's saved delivery mode;
* foreground input is admitted only after exact Cua/GNOME presentation proof.

It also teaches Hermes' slash completer the skill's reserved operator
subcommands. Natural ``/computer-use <task>`` remains a normal skill invocation.
"""
from __future__ import annotations

import copy
import json
import os
import subprocess
import sys
from pathlib import Path

_INPUT_ACTIONS = frozenset({
    "click", "double_click", "right_click", "middle_click",
    "drag", "scroll", "type", "key",
})
_TRUE = frozenset({"on", "yes", "true", "1", "background"})
_SUBCOMMANDS = (
    "status",
    "trace",
    "present",
    "background",
    "managed",
    "truths",
    "consent",
    "doctor",
    "help",
)


def _standing_delivery_mode() -> str:
    raw = os.getenv("GWCU_BACKGROUND_PRIORITY")
    if raw is None:
        state_home = Path(os.getenv("XDG_STATE_HOME", str(Path.home() / ".local/state")))
        path = state_home / "gnome-wayland-computer-use" / "background-priority"
        try:
            raw = path.read_text().strip()
        except OSError:
            raw = "off"
    return "background" if str(raw).strip().casefold() in _TRUE else "foreground"


def _presenter() -> Path:
    override = os.getenv("GWCU_PRESENTER")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".agents/skills/gnome-wayland-computer-use/scripts/present-window.py"


def _exact_target(call: dict) -> tuple[int, int] | None:
    pid = call.get("pid")
    window_id = call.get("window_id")
    if (
        isinstance(pid, int)
        and not isinstance(pid, bool)
        and pid > 0
        and isinstance(window_id, int)
        and not isinstance(window_id, bool)
        and 0 <= window_id <= (1 << 32) - 1
    ):
        return pid, window_id
    return None


def _present_exact(call: dict) -> dict:
    target = _exact_target(call)
    if target is None:
        return {
            "ok": False,
            "code": "exact_target_required_for_foreground",
            "detail": "foreground native input requires exact integer pid + window_id",
        }
    pid, window_id = target
    presenter = _presenter()
    try:
        proc = subprocess.run(
            [
                sys.executable,
                str(presenter),
                "present",
                "--pid",
                str(pid),
                "--window-id",
                str(window_id),
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=5,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"ok": False, "code": "presentation_transport_failed", "detail": str(exc)}
    try:
        result = json.loads(proc.stdout.strip()) if proc.stdout.strip() else {}
    except json.JSONDecodeError:
        result = {"ok": False, "code": "presentation_invalid_output", "detail": proc.stdout[:1024]}
    if proc.returncode != 0 and result.get("ok") is not False:
        result = {"ok": False, "code": "presentation_failed", "detail": proc.stderr[:1024]}
    return result


def _wrap_builtin(handler):
    def gwcu_computer_use(args: dict, **kwargs):
        call = dict(args or {})
        action = call.get("action")
        if action in _INPUT_ACTIONS:
            if "delivery_mode" not in call:
                call["delivery_mode"] = _standing_delivery_mode()
            if call.get("delivery_mode") == "foreground":
                presentation = _present_exact(call)
                if not presentation.get("ok"):
                    raise RuntimeError(
                        "GWCU refused foreground input before actuation: "
                        + json.dumps(presentation, separators=(",", ":"))
                    )
        return handler(call, **kwargs)

    return gwcu_computer_use


def _override_allowed(ctx) -> bool:
    """Honor modern capability consent; recognize the pre-capability API."""
    has_capability = getattr(ctx, "has_capability", None)
    if callable(has_capability):
        return bool(has_capability("tools.override"))
    return callable(getattr(ctx, "register_tool", None))


def _install_completion_contract(ctx) -> None:
    """Expose GWCU operator verbs after ``/computer-use `` in Hermes CLI.

    Hermes normally treats text after a skill slash as either another stacked
    skill or free-form task text and therefore returns before its static
    subcommand completer. GWCU is intentionally dual-use (task + operator
    subcommands), so mark this one skill as non-stackable *for completion only*
    and publish its reserved verbs in the ordinary SUBCOMMANDS table. Runtime
    skill dispatch is untouched.
    """
    try:
        from hermes_cli import commands as commands_mod

        commands_mod.SUBCOMMANDS["/computer-use"] = list(_SUBCOMMANDS)
        cls = commands_mod.SlashCommandCompleter
        marker = "_gwcu_original_is_skill_command"
        if not hasattr(cls, marker):
            original = cls._is_skill_command
            setattr(cls, marker, original)

            def _gwcu_is_skill_command(self, token: str) -> bool:
                normalized = self._normalize_skill_token(token)
                if normalized == "/computer-use":
                    return False
                return original(self, token)

            cls._is_skill_command = _gwcu_is_skill_command

            on_unload = getattr(ctx, "on_unload", None)
            if callable(on_unload):
                def restore() -> None:
                    try:
                        cls._is_skill_command = getattr(cls, marker)
                        delattr(cls, marker)
                        commands_mod.SUBCOMMANDS.pop("/computer-use", None)
                    except Exception:
                        pass
                on_unload(restore)
    except Exception:
        # Completion enrichment is ergonomic only; runtime control policy must
        # still load even on an older Hermes build without this completer.
        pass


def register(ctx):
    """Enforce control policy and install /computer-use completion metadata."""
    _install_completion_contract(ctx)

    if not _override_allowed(ctx):
        return None

    try:
        from tools.computer_use.schema import COMPUTER_USE_SCHEMA
        from tools.computer_use.tool import handle_computer_use
    except Exception:
        return None

    schema = copy.deepcopy(COMPUTER_USE_SCHEMA)
    schema["description"] = (
        "GWCU control authority for Ubuntu GNOME Wayland via cua-driver. "
        "Default foreground native input MUST include exact pid and window_id; "
        "GWCU first proves persistent visible presentation through Cua's "
        "GNOME helper, then admits the input. Use list_windows to resolve the "
        "exact target before mutation. For typed browser work, bind the exact "
        "native browser pid/window_id and keep visible presentation as a "
        "separate postcondition. "
        + str(schema.get("description", ""))
    )
    ctx.register_tool(
        name="computer_use",
        toolset="computer_use",
        schema=schema,
        handler=_wrap_builtin(handle_computer_use),
        override=True,
    )
    return None
