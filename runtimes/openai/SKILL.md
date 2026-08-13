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

Use **Cua Driver as the control authority**. This skill exists to make Cua fast,
well-provisioned, and predictable on Ubuntu GNOME Wayland, plus provide an
independent whole-screen observation surface.

> **Cua decides mechanics. The agent decides intent.**

Cua owns semantic and pixel actions, window state, GNOME geometry, verified
activation, input delivery, cursor behavior, post-action effects, escalation,
and structured refusals. Do not recreate those mechanisms with shell scripts,
AT-SPI calls, WinRects D-Bus calls, `ydotool`, `/dev/uinput`, or guessed focus.

## Workflow Contract

Take control and do the requested work.

For a **known target**, begin with one useful Cua target/window state. Reuse the
semantics and pixels in that state. Use a grounded semantic element when one
exists; otherwise use coordinates from the same target screenshot. Consume
Cua's returned effect, verification, and delivery result rather than predicting
application behavior.

For an **unknown target**, resolve identity once. Enumerate apps/windows only if
the requested target remains genuinely ambiguous. Use whole-screen observation
only when target-scoped Cua evidence cannot bind what the user means.

For a **terminal/admin task**, use the terminal directly.

Ask only when target, outcome, or authorization is materially ambiguous.

Do not run update checks, broad diagnostics, capability inventories, or
whole-screen capture before a normal task.

## Execution State Machine

```text
known target
    ↓
one Cua target/window state
    ├─ semantic control grounded → Cua AX action
    └─ visual control only        → Cua PX action from the same state
                                     ↓
                               consume Cua verdict
                                     ├─ confirmed      → continue
                                     ├─ px             → use Cua PX once
                                     ├─ foreground     → let Cua verify/activate exact target
                                     ├─ unverifiable   → cheapest fresh Cua verification
                                     └─ refusal/unsafe → respect refusal; choose only a genuinely different safe route

unknown target
    ↓
app-identity.sh --resolve --machine "<name>"
    ├─ resolved  → Cua target state
    ├─ ambiguous → minimal disambiguation
    └─ missing   → Cua discovery, then whole-screen observation only if needed

host contradiction
    ↓
profile.sh read
    ├─ current state explains it → follow `next`
    └─ stale/missing             → profile.sh refresh or diagnose.sh --machine once
```

Never retry the same failed Cua delivery shape blindly. Never answer a Cua
refusal by injecting raw keyboard or pointer input into the current foreground.

## Foreground Preservation Contract

Preserve the user's foreground by default.

Cua on GNOME owns the WinRects-backed target geometry and exact activation
contract. If Cua requires foreground delivery, let Cua activate and verify the
exact target before focus-bound input. Do not infer foreground need from toolkit
labels such as GTK, Electron, browser, Vulkan, or GLFW.

A structured refusal is useful information, not permission to bypass Cua.

## Latency-First Interaction

Spend a model/tool round-trip only when a decision can change.

- Known app means no `list_apps` / `list_windows` ceremony.
- Reuse one Cua state across AX → PX when it supplies both.
- Use one complete typing action, not character loops.
- Send a shortcut in one key action.
- Prefer semantic `set_value` when it directly establishes the requested value.
- Let a confirmed click flow directly into deterministic typing when appropriate.
- Use Cua action capture/read-back when it already proves the postcondition.
- Wait only for a real asynchronous transition.
- Cache resolved identity until the target disappears or contradicts it.
- Whole-screen observation is discovery or an explicit user request, not a universal prelude.
- Diagnostics and update checks stay off the success path.

Ideal shape:

```text
Cua state once → deterministic Cua action span → verify at the next real decision boundary
```

## Pixel-Only Surfaces

An AT-SPI-empty Vulkan, GLFW, game, canvas, video, or custom-rendered window is
**pixel-only**, not absent.

If Cua resolves the GNOME window, use that target's screenshot and compositor
geometry. Do not launch a desktop-wide search merely because the AX tree is
empty. Let Cua decide whether delivery can remain targeted or must use verified
foreground.

If Cua cannot safely address the requested delivery shape, respect its refusal.

## Whole-Screen Observation

Cua remains the control authority. This project separately owns explicit
whole-screen observation through XDG ScreenCast + PipeWire:

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/observe.sh" --media --screen
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
```

The lazy observer keeps a portal-scoped PipeWire stream warm during a short task
burst. Installation and login do not open capture consent. User cancellation is
terminal for that request.

Use this path when the user asks about the whole visible screen/desktop or when
Cua target evidence cannot yet bind the intended object.

## Deterministic Helpers

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/cua-health.py"
"$ROOT/scripts/app-identity.sh" --resolve --machine "ChatGPT"
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/profile.sh" read --machine
"$ROOT/scripts/profile.sh" refresh --machine
"$ROOT/scripts/diagnose.sh" --machine
```

`cua-health.py` is a thin direct-MCP transport for Cua's stable `health_report`
contract. It preserves Cua's versioned `structuredContent`; it does not
reconstruct Cua health. `diagnose.sh` combines that upstream verdict with only
the GNOME/session, WinRects session state, and independent observation facts
this project owns. `cua-driver doctor --json` remains supplemental diagnostic
detail. Top-level `ok` means the installed system is actually ready now.

## Cua GNOME Integration

`winrects@cua` belongs to Cua. Never call `org.cua.WinRects` directly, vendor the
helper, duplicate its protocol, or maintain a parallel input stack.

The installer invokes only Cua's packaged helper:

```text
~/.cua-driver/packages/current/wayland-helper/install.sh
```

One GNOME sign-out/in may be required after a new or updated helper. Native
whole-screen observation can already be ready before that reload.

## Maintenance

```bash
"$HOME/.agents/skills/gnome-wayland-computer-use/scripts/check-update.sh" --force
"$HOME/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh"
```

Maintenance is explicit. It is never required before the first normal action.
