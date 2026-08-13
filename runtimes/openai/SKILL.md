---
name: computer-use
description: Operate Ubuntu GNOME Wayland through Cua Driver.
version: 2.3.0
author: Ryan Raposo
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [computer-use, cua, desktop, automation, gui, gnome, wayland, accessibility]
    category: desktop
    related_skills: [gnome-wayland-reload]
    requires_toolsets: [computer_use, terminal]
---

# Computer Use on Ubuntu GNOME Wayland

Use **Cua Driver as the control authority**. GWCU prepares Ubuntu/GNOME once,
keeps whole-screen observation independent, and turns recurring desktop
reasoning into deterministic local information.

> **The model decides intent. Scripts collapse uncertainty. Cua executes.**

Cua owns semantic and pixel actions, target/window state, GNOME geometry,
verified activation, input delivery, cursor behavior, effects, escalation, and
structured refusals. Never recreate those mechanisms with AT-SPI scripts,
WinRects D-Bus calls, `ydotool`, `/dev/uinput`, or guessed focus.

## GNOME Portal Contract

**GNOME Wayland is the intended session. No X11 or XWayland session is required.**

The first Cua foreground input may show GNOME's **Remote Desktop / remote
control** consent. Cua uses the portal-issued EIS/libei session. A denial or
cancellation is terminal for that attempt and must not be bypassed.

Explicit whole-screen observation uses a separate **ScreenCast** portal session
and may have its own screen-selection consent.

## Call Budget

Spend a model/tool round-trip only when it can change the next action.

| Situation | GWCU setup calls before useful work |
|---|---:|
| known app/window | **0** |
| ambiguous app identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen observation | **1** — `observe.sh` |

A known target goes directly to Cua. Do not ceremonially preflight the host.

## Workflow Contract

Take control and do the requested work. Ask only when target, outcome, or
authorization is materially ambiguous. For a terminal/admin task, use the
terminal directly.

Keep normal computer use target-scoped. Diagnostics, update checks, host
inventories, and whole-screen capture stay off the success path unless the task
or returned evidence genuinely requires them.

## Execution State Machine

### Known target

Start with one useful Cua target/window state. Reuse semantics and pixels from
that state. Use a grounded semantic element when one exists; otherwise act from
the same target pixels. Consume Cua's effect, verification, delivery result, and
escalation instead of predicting application behavior.

```text
known target
→ one Cua target/window state
→ AX when grounded / PX from the same state when visual
→ deterministic Cua action span
→ verify only at the next real decision boundary
```

### Unknown or browser-backed target

Do **one local routing call**:

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/profile.sh" route --machine "<target name>"
```

`gwcu.route.v1` returns one of:

```text
target_resolved  → give the original target + identity evidence to Cua
live_target      → launcher metadata is absent; ask Cua for live target state
target_ambiguous → disambiguate from the returned candidates
```

This command composes cached session context with the deterministic launcher
resolver locally. It does **not** run diagnostics or refresh host state merely
because an app identity was uncertain.

Do not separately call `app-identity.sh`, `profile.sh read`, and app/window
enumeration when this one route call answers the uncertainty.

### Host contradiction

If a result contradicts the installed/runtime state, make **one recovery call**:

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

That command reads the cached session profile and, only when it is stale or
missing, refreshes it through `diagnose.sh` inside the same shell invocation. It
returns `host_ready` or `host_recovery` plus the deterministic `next` action.

Do not make the model perform `read → refresh → diagnose` as separate tool calls.

### Whole screen

For an explicit whole-screen/desktop request, or only when target-scoped Cua
evidence cannot bind the requested object:

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/observe.sh" --media --screen
```

The lazy observer keeps a portal-scoped PipeWire stream warm for a short task
burst. Installation/login itself does not open capture consent.

## Latency-First Interaction

- Known app means no `list_apps` / `list_windows` ceremony.
- No update checks, broad diagnostics, capability inventories, or whole-screen
  capture before a normal task.
- Reuse one Cua state across AX → PX when it supplies both.
- Use one complete typing action, not character loops.
- Send a shortcut in one key action.
- Prefer semantic `set_value` when it directly establishes the value.
- Let a confirmed click flow into deterministic typing when appropriate.
- Use Cua read-back when it already proves the postcondition.
- Wait only for a real asynchronous transition.
- Cache resolved identity until the target disappears or contradicts it.
- Never retry the same failed delivery shape blindly.
- Never answer a Cua refusal with raw pointer/keyboard injection.

The ideal runtime shape is intentionally boring:

```text
Cua state once → useful action span → next decision boundary
```

## Foreground Preservation

Preserve the user's foreground by default. Cua owns exact target activation
through its GNOME integration. If foreground delivery is required, let Cua
activate and verify the exact target. Do not infer foreground need from toolkit
labels such as GTK, Electron, browser, Vulkan, or GLFW.

A structured refusal is capability information, not permission to bypass Cua.

## Pixel-Only Surfaces

An AT-SPI-empty Vulkan, GLFW, game, canvas, video, or custom-rendered window is
**pixel-only**, not absent.

If Cua resolves the GNOME window, use that target's pixels and compositor
geometry. Do not launch a desktop-wide search because the AX tree is empty.

## Deterministic Script Surface

The agent-facing helpers are deliberately small:

```bash
# uncertainty → one route
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"

# host contradiction → one recovery verdict
"$ROOT/scripts/profile.sh" recover --machine

# explicit whole-screen evidence → one observation
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
```

Lower-level helpers exist so scripts can compose scripts without spending model
turns:

```text
app-identity.sh    deterministic launcher/PWA identity
profile.sh read    passive cached session truth
profile.sh refresh → diagnose.sh → Cua health + GNOME observation health
cua-health.py      thin transport for Cua health_report structuredContent
```

Prefer the composed commands above. Call lower-level helpers directly only for
maintenance, testing, or when their raw detail is the actual requested output.

Top-level `ok=true` means the installed system is ready now. `cua-driver doctor
--json` is supplemental diagnostic detail; Cua's stable `health_report` is
upstream control-health truth.

## Cua GNOME Integration

GWCU qualifies Cua Driver **0.19.3**. Agents must not update Cua as task-time
housekeeping.

`winrects@cua` belongs to Cua. Never call `org.cua.WinRects` directly, vendor the
helper, duplicate its protocol, or maintain a parallel input stack.

One GNOME sign-out/in may be required after installing or updating that helper.

## Maintenance

```bash
"$ROOT/scripts/check-update.sh" --force
"$ROOT/scripts/diagnose.sh"
```

Maintenance is explicit and stays off the normal action path.
