---
name: computer-use
description: Operate Ubuntu GNOME through Cua Driver.
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

# Computer Use on Ubuntu GNOME

Use **Cua Driver as the control authority**. GWCU prepares Ubuntu/GNOME once,
turns recurring mechanics into deterministic local programs, remembers only
stable project-local routing truths when allowed, and keeps whole-screen
observation independent.

> **The model decides intent. Programs collapse mechanics. Cua executes.**

Cua owns semantic and pixel actions, target/window state, GNOME geometry,
verified activation, input delivery, cursor behavior, effects, escalation, and
structured refusals. Never recreate those mechanisms with AT-SPI scripts,
WinRects D-Bus calls, `ydotool`, `/dev/uinput`, or guessed focus.

## GNOME Portal Contract

GNOME Wayland is the intended session. **No X11 or XWayland session is
required.**

Cua uses GNOME's `org.freedesktop.portal.RemoteDesktop` API to obtain a local
pointer/keyboard EIS/libei session. The installer normally establishes this
one-time permission before declaring the machine ready. GNOME may label the UI
"Remote Desktop" or "remote control"; this integration does not install an
RDP/VNC server, a raw-input daemon, or a project input udev rule.

A separate explicit whole-screen observation uses ScreenCast and may have its
own screen-selection consent. A denial/cancellation is terminal for that
attempt and must not be bypassed.

## Call Budget

Spend a model/tool round-trip only when it can change the next action.

| Situation | GWCU setup calls before useful work |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
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

Use the execution mechanism that matches the work:

```text
stable recurring mechanics → repository script
one-off mechanical fan-out → execute_code
independent reasoning       → delegate_task
bounded long process        → terminal(background=true, notify_on_complete=true)
real user choice            → clarify
interactive desktop action  → parent Cua loop
```

Keep portal consent and user-facing desktop decisions in the parent session.
Delegate independent research/context work, not the interactive control loop.
When `clarify` offers choices, put the recommended choice first. Prefer
`execute_code` over a chain of agent/tool calls when the sequence is one-off but
fully programmatic.

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

Inside that call:

```text
project AGENTS truth lookup
→ launcher/PWA resolver only on miss
→ stable truth write-back only when enabled + confidently resolved
→ gwcu.route.v1
```

`gwcu.route.v1` returns one of:

```text
target_resolved  → give the original target + identity evidence to Cua
live_target      → stable launcher metadata is absent; ask Cua for live target state
target_ambiguous → disambiguate only the returned candidates
```

Managed project truths are acceleration hints, never authority. **Live Cua state
wins on contradiction.** Do not separately call `app-identity.sh`,
`profile.sh read`, and app/window enumeration when this route call answers the
uncertainty.

### Host contradiction

If a result contradicts the installed/runtime state, make **one recovery call**:

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

That command reads cached session truth and, only when stale/missing, refreshes
through `diagnose.sh` inside the same shell invocation.

Do not make the model perform `read → refresh → diagnose` as separate tool calls.

### Whole screen

For an explicit whole-screen/desktop request, or only when target-scoped Cua
evidence cannot bind the requested object:

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/observe.sh" --media --screen
```

The lazy observer keeps a portal-scoped PipeWire stream warm for a short task
burst. Installation/login itself does not open ScreenCast consent.

## Managed Project Truths

When enabled, `profile.sh route` may maintain a bounded managed block in the
current Git worktree's root `AGENTS.md`.

Only stable low-churn identity fields are eligible: display name, desktop ID,
app ID, `StartupWMClass`, and app kind. Never store screenshots, user text,
timestamps, health snapshots, coordinates, geometry, focus, task history, or
other transient state.

The managed block is bounded, deterministic, regex-addressable, comment-safe,
and preserves user-authored content outside its markers. A warm project-memory
hit can remove **100% of the repeat identity-routing setup call**.

Persistent preference:

```bash
"$ROOT/scripts/profile.sh" managed on --machine
"$ROOT/scripts/profile.sh" managed off --machine
"$ROOT/scripts/profile.sh" managed status --machine
```

`GWCU_PROJECT_MEMORY=off` is the runtime override.

## Hermes `/computer-use`

When the Hermes plugin is installed, its native command registry exposes:

```text
/computer-use status
/computer-use managed
/computer-use managed on|off|status
/computer-use consent
/computer-use doctor
/computer-use help
```

`/computer-use managed` enables managed project truths. `/computer-use consent`
explains and verifies the local RemoteDesktop → EIS/libei contract. The command
is registered through Hermes's plugin API so `/computer-use` appears in command
discovery/autocomplete with its description and argument hint.

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
- Cache stable identity through the managed project truth layer when enabled.
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
# target uncertainty → one route
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"

# host contradiction → one recovery verdict
"$ROOT/scripts/profile.sh" recover --machine

# explicit whole-screen evidence → one observation
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png

# user-facing installed-system commands
"$ROOT/scripts/computer-use.sh" status
```

Lower-level helpers exist so programs can compose programs without spending
model turns:

```text
app-identity.sh     deterministic launcher/PWA identity
profile.sh read     passive cached session truth
profile.sh refresh  → diagnose.sh → Cua health + GNOME observation health
portal-control.py   RemoteDesktop contract + one-time pointer-only authorization
cua-health.py       thin transport for Cua health_report structuredContent
```

Prefer the composed commands above. Call lower-level helpers directly only for
maintenance, testing, or when their raw detail is the requested output.

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
"$ROOT/scripts/portal-control.py" --status
```

Maintenance is explicit and stays off the normal action path.
