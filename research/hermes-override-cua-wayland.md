# Hermes tools.override + Cua delivery_mode inventory + Ubuntu 26 Wayland

**Date:** 2026-11-13
**Repo:** /home/ryan/repos/gnome-wayland-computer-use
**Branch:** dev (from main)

## Hermes `tools.override` (confirmed against hermes-agent docs/source)

- `runtimes/hermes/plugin.yaml` declares `capabilities: [tools.override]`, matching the Hermes plugin capability spec.
- `ctx.register_tool(name, toolset, schema, handler, override=True)` replaces a built-in tool; `override=True` against a built-in requires the operator consent gate (`plugins.entries.<plugin_id>.allow_tool_override` or the consent-flow `tools.override` grant).
- `ctx.has_capability("tools-override")` probes consent; bundled plugins are trusted by default for `tools.override` and degrade gracefully otherwise.
- GWCU plugin's `_override_allowed(ctx)` already matches the Hermes API exactly: `ctx.has_capability("tools.override")` with fallback to `callable(getattr(ctx, "register_tool", None))` for pre-capability builds.
- `register_tool` signature `(name, toolset, schema, handler, check_fn=None, requires_env=None, is_async=False, description="", emoji="", override=False)` matches the plugin's call. **No signature drift.**
- `register(ctx)` currently returns `None` in all paths (override not allowed, import failure, success). A diagnostic dict return is untested by GWCU; verify with `tests/hermes.sh`.

## Cua `delivery_mode` action inventory (confirmed via action-span.py)

- `scripts/action-span.py` `tool_modes()` (lines 359-370) calls Cua `tools/list` over MCP and treats **any** tool whose `inputSchema.properties` contains `"delivery_mode"` as foreground-capable. New Cua tools inherit the gate without a list update.
- SKILL.md "Foreground action coverage" matrix:
  - Pointer input: click, double_click, right_click, middle_click, drag, scroll → exact `(pid, window_id)` → PRESENT → `delivery_mode="foreground"`.
  - Text/keyboard input: type, key → same gate. (Lower-level Cua span equivalents: `type_text`, `press_key`, `hotkey` — these are Cua MCP tool names, not Hermes `computer_use` action names; Hermes exposes them as `type`/`key`.)
  - Closed local app: launch_app → ACQUIRE through Cua, handled separately in `_wrap_builtin` before the foreground-action check, so it is **not** in `_FOREGROUND_ACTIONS`.
  - Direct AX value mutation: set_value → semantic mutation; does not substitute for PRESENT when the result must be visible. Gated in foreground mode only; background-mode set_value passes through ungated.
  - Observation/waits (capture, wait, list_apps, list_windows): read-only, no gate.
- Cua docs confirm `delivery_mode: "foreground"` is supported on the Linux/Wayland desktop; input routes through GNOME RemoteDesktop → EIS/libei.

## Ubuntu 26.04 GNOME Wayland (confirmed)

- Stock Ubuntu 26.04 (Resolute Raccoon) is GNOME 50, Wayland-only; no default X11/Xorg session.
- Input injection: `xdg-desktop-portal` `RemoteDesktop` → EIS/libei, one-time consent dialog, `restore_token` can persist approval.
- Screen capture: ScreenCast portal → PipeWire (separate consent).
- Mutter does not implement `zwlr_virtual_pointer`/`wlr-screencopy` (wlroots-specific); GNOME routes capture/input through the portal by design.
- No X11 or XWayland session required.

## `_FOREGROUND_ACTIONS` (final set)

click, double_click, right_click, middle_click, drag, scroll, type, key, set_value

launch_app is ACQUIRE (handled separately, not PRESENT-gated).
capture/wait/list_apps/list_windows are read-only (not in the set).

## Coverage matrix

| Action | in old `_INPUT_ACTIONS` | exposes delivery_mode | foreground gate required |
|---|---|---|---|
| click | yes | yes | yes |
| double_click | yes | yes | yes |
| right_click | yes | yes | yes |
| middle_click | yes | yes | yes |
| drag | yes | yes | yes |
| scroll | yes | yes | yes |
| type | yes | yes | yes |
| key | yes | yes | yes |
| set_value | **no** | yes | yes (foreground only) |
| launch_app | n/a (ACQUIRE) | n/a | no (acquisition, handled separately) |
| capture/wait/list_* | no | read-only | no |
