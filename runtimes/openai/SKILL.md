---
name: computer-use
description: Control Ubuntu GNOME Wayland apps, capture, and input.
version: 2.3.0
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

Use the installed operating layer; do not re-derive its architecture during a task.

> **Accessibility when semantics exist. Pixels when they do not. Compositor precision when GNOME requires it. Machine verdicts instead of ritual deliberation.**

Four planes exist beneath the runtime:

- **Observation:** XDG ScreenCast + PipeWire, with a lazy persistent observer.
- **Semantics:** AT-SPI / Cua AX.
- **GNOME precision:** Cua + its bundled `winrects@cua` Mutter adapter.
- **Recovery:** verified foreground, then `/dev/uinput` + `ydotool` only when warranted.

The agent decides intent. The operating layer decides mechanics.

## Workflow Contract

Take control and do the requested work.

For a **known target**, start with one useful Cua window state. Current Cua window
state supplies semantics and pixels together. Use a semantic element when it is
grounded; otherwise use coordinates from that same target screenshot. Follow
the runtime's returned `effect`, verification, and escalation result instead of
predicting toolkit behavior.

For an **unknown target**, resolve identity once. Enumerate apps/windows only if
the requested target remains genuinely ambiguous. Use whole-screen observation
only when target-level evidence cannot bind the thing the user means.

For a **terminal/admin task**, use the terminal directly. Do not route shell work
through GUI automation.

Ask only when target, outcome, or authorization is materially ambiguous.
Preview destructive, privileged, external, or irreversible effects as required
by the governing authorization policy.

Do not run update checks, broad diagnostics, or capability inventories before a
normal task. They are maintenance/failure tools, not a ritual preflight.

## Execution State Machine

```text
known target
    ↓
one Cua target/window state
    ├─ semantic control grounded → AX action
    └─ visual control only        → PX action from the same screenshot
                                     ↓
                               consume runtime verdict
                                     ├─ confirmed          → continue
                                     ├─ px                 → PX once
                                     ├─ foreground         → exact verified foreground once
                                     ├─ unverifiable       → cheapest fresh verification
                                     └─ refusal/unsafe     → stop or choose a genuinely different route

unknown target
    ↓
live identity
    ↓ if genuinely ambiguous
app-identity.sh --resolve --machine "<name>"
    ├─ resolved  → use it
    ├─ ambiguous → minimal disambiguation
    └─ missing   → live window / visible-screen discovery

capability contradiction
    ↓
profile.sh read
    ├─ explains failure → act on that fact
    └─ stale/missing    → profile.sh refresh or diagnose.sh --machine once
```

Never retry the same failed delivery rung blindly.

Treat element indices and visual coordinates as state-bound. Invalidate them
after navigation, structural mutation, window replacement, major layout change,
or a runtime result that says the cached target is stale.

## Foreground Preservation Contract

Preserve the user's foreground by default.

Use background semantic delivery when the runtime can safely address the target.
If Cua returns a foreground escalation, activate the exact intended GNOME window
and rely on Cua's focus verification before focus-bound input. Do not infer
foreground need from “GTK”, “Electron”, “browser”, or any other toolkit label.

A refusal such as `background_unavailable`, `background_occluded`, or an unsafe
target result is useful information. It is never permission to inject input into
whichever app happens to be focused.

Escalation is:

```text
background semantic
→ target-addressed PX/semantic delivery
→ exact verified foreground
→ explicit recovery when appropriate
→ structured refusal
```

## Latency-First Interaction

Spend a model/tool round-trip only when a decision can change.

- Known app means **no `list_apps` / `list_windows` ceremony**.
- Reuse one Cua state snapshot across AX → PX when the runtime supplies both.
- Use one complete `type(text="...")` call, not chunk/character loops.
- Send a shortcut in one key action.
- Prefer semantic `set_value` when it establishes the requested value directly.
- A confirmed click may flow directly into deterministic typing.
- A known submit shortcut may follow verified typing without an intermediate screenshot.
- Use `capture_after=true` when the live runtime offers it and the action needs visual verification.
- If structured read-back already proves the postcondition, do not capture again.
- Use `wait` only for a real asynchronous transition.
- Cache resolved app identity until the target disappears or contradicts it.
- Whole-screen capture is discovery/explicit observation, not a universal prelude.
- Diagnostics and update checks stay off the success path.

The ideal task shape is:

```text
observe once → deterministic action span → verify at the next true decision boundary
```

## Pixel-Only Surfaces

A visible Vulkan, GLFW, game, canvas, custom renderer, video surface, or other
AT-SPI-empty window is **pixel-only**, not absent.

If Cua resolves the GNOME window, use that target's screenshot and compositor
geometry. Do not launch a desktop-wide search merely because the AX tree is
empty. Bring the exact target forward only when the runtime says focus-bound
delivery is required.

If no trustworthy window binding exists, use whole-screen observation to
discover the target, bind it, then return to target-scoped operation. If an
occluded target cannot be safely addressed, surface that limitation rather than
guessing input.

## Deterministic Helpers

These helpers turn host facts into small machine verdicts.

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/app-identity.sh" --resolve --machine "ChatGPT"
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/profile.sh" read --machine
"$ROOT/scripts/profile.sh" refresh --machine
"$ROOT/scripts/diagnose.sh" --machine
```

Machine helpers use stable envelopes with `ok`, `code`, `result`, and `next`.
Treat `terminal=true` as terminal for that request. Follow a deterministic
`next.action` when it is safe and relevant; do not invent a parallel recovery
ladder.

## Whole-Screen Observation

Use whole-screen pixels when the user asks about the screen/desktop or when a
target cannot otherwise be bound:

```bash
"$HOME/.agents/skills/gnome-wayland-computer-use/scripts/observe.sh" --media --screen
```

`--desktop` is a compatibility alias for the same visible display.

The observation facade prefers a lazy socket-activated ScreenCast broker. The
broker keeps the portal session, portal-scoped PipeWire remote, and raw stream
warm for a short task burst, then closes them on idle. Installation and login do
not open screen-capture permission UI. If the broker is unavailable, the direct
`capture.sh` implementation remains an independent fallback.

A ScreenCast consent cancellation is terminal for that request. Never answer a
cancelled picker by opening Screenshot or synthetic-key capture UI.

## Cua GNOME Precision

Use the runtime's own Cua capabilities. Do not call `org.cua.WinRects` directly,
vendor Cua's helper, duplicate its D-Bus protocol, or make project observation
depend on it.

For the Hermes/Cua profile, `winrects@cua` is Cua's Mutter adapter. Cua may use
it for authoritative window geometry, GTK4 coordinate reconstruction, exact
activation/focus verification, compositor capture, and its agent cursor.

If `GNOME precision` is `reload_required`, native ScreenCast and AT-SPI can
still work; one GNOME sign-out/in activates a newly installed/updated helper.

## Hermes Action Vocabulary

Use only arguments present in the live `computer_use` schema. Common operations:

```text
capture / window state
click / double_click / right_click
drag / scroll
type
key
set_value
wait
list_apps / list_windows       # discovery only
focus_app                      # only when target activation is actually needed
```

Prefer element addressing when semantics ground the intended control. Prefer
coordinates from the already-returned target screenshot for pixel-only controls.

## Recovery and Maintenance

`/dev/uinput` + `ydotool` are recovery infrastructure, not the normal action
surface. Use them only when the requested operation has reached that rung and
the target is safe.

Read `references/skill-ux-contract.md` for ambiguity, authorization, mutation,
and proof obligations.

Maintenance commands are explicit:

```bash
"$HOME/.agents/skills/gnome-wayland-computer-use/scripts/check-update.sh" --force
"$HOME/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh"
```

They are never required before the first normal computer-use action.
