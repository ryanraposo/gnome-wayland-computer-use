"""Hermes integration for gnome-wayland-computer-use.

The installed skill owns the /computer-use slash command. This plugin never
registers a slash command. On Hermes versions that expose the documented
``tools.override`` capability it wraps the built-in ``computer_use`` tool so
GWCU's saved background-priority preference is enforced mechanically instead
of depending on the model to remember a delivery_mode argument.
"""
from __future__ import annotations

import copy
import os
from pathlib import Path

_INPUT_ACTIONS = frozenset({
    "click", "double_click", "right_click", "middle_click",
    "drag", "scroll", "type", "key",
})
_TRUE = frozenset({"on", "yes", "true", "1", "background"})


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


def _wrap_builtin(handler):
    def gwcu_computer_use(args: dict, **kwargs):
        call = dict(args or {})
        action = call.get("action")
        if action in _INPUT_ACTIONS and "delivery_mode" not in call:
            call["delivery_mode"] = _standing_delivery_mode()
        return handler(call, **kwargs)

    return gwcu_computer_use


def register(ctx):
    """Keep slash ownership in the skill; enforce tool policy when consented."""
    has_capability = getattr(ctx, "has_capability", None)
    if not callable(has_capability) or not has_capability("tools.override"):
        return None

    try:
        from tools.computer_use.schema import COMPUTER_USE_SCHEMA
        from tools.computer_use.tool import handle_computer_use
    except Exception:
        # Older Hermes builds keep the skill useful even when the tool-override
        # seam is unavailable. The runtime contract still supplies explicit
        # delivery_mode on mutating computer_use calls.
        return None

    schema = copy.deepcopy(COMPUTER_USE_SCHEMA)
    schema["description"] = (
        "GWCU control authority for the host desktop via cua-driver. "
        "Use this for native applications and browser windows, including the "
        "cua_browser_* actions when Cua advertises an exact browser route. "
        "GWCU applies its saved foreground/background delivery preference to "
        "native input when delivery_mode is omitted. "
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
