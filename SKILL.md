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
turns recurring mechanics into deterministic local programs, stores only useful
durable local truth in `.gwcu` when managed truth is enabled, and keeps
whole-screen observation independent.

> **The model decides intent. Programs collapse mechanics. Cua executes.**

Cua owns semantic and pixel actions, target/window state, GNOME geometry,
verified activation, input delivery, cursor behavior, effects, escalation, and
structured refusals. Never recreate those mechanisms with AT-SPI scripts,
WinRects D-Bus calls, `ydotool`, `/dev/uinput`, or guessed focus.

## GNOME portal contract

GNOME Wayland is the intended session. **No X11 or XWayland session is
required.**

Cua uses GNOME's `org.freedesktop.portal.RemoteDesktop` API to obtain a local
pointer/keyboard EIS/libei session. The installer normally establishes this
one-time permission before declaring the machine ready. GNOME may label the UI
"Remote Desktop" or "remote control"; this integration does not install an
RDP/VNC server, raw-input daemon, or project input udev rule.

A separate explicit whole-screen observation uses ScreenCast and may have its
own screen-selection consent. Denial/cancellation is terminal for that attempt.

## Call budget

Spend a model/tool round-trip only when it can change the next action.

| Situation | GWCU setup calls before useful work |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen observation | **1** — `observe.sh` |

A known target goes directly to Cua. Do not ceremonially preflight the host.

## Workflow contract

Take control and do the requested work. Ask only when target, outcome, or
authorization is materially ambiguous. For terminal/admin tasks, use the
terminal directly.

Keep normal computer use target-scoped. Diagnostics, update checks, host
inventories, and whole-screen capture stay off the success path unless returned
evidence or the task genuinely requires them.

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
Delegate independent reasoning, not the interactive control loop. Prefer
`execute_code` over a chain of model/tool calls when a sequence is fully
programmatic.

## Execution state machine

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

Inside that one call:

```text
repo/workspace .gwcu lookup
→ deterministic launcher/PWA resolver only on miss
→ stable exact identity written back only when managed truth is enabled
→ gwcu.route.v1
```

`gwcu.route.v1` returns one of:

```text
target_resolved  → give target + identity evidence to Cua
live_target      → launcher metadata is absent; ask Cua for live target state
target_ambiguous → disambiguate only the returned candidates
```

`.gwcu` is an acceleration surface, never control authority. **Live Cua state
wins on contradiction.** Do not separately call `app-identity.sh`,
`profile.sh read`, diagnostics, and app/window enumeration when `route` already
answers the uncertainty.

### Host contradiction

If a result contradicts installed/runtime state, make **one recovery call**:

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

That command reads cached session truth and, only when stale/missing, refreshes
through `diagnose.sh` inside the same invocation.

Do not make the model perform `read → refresh → diagnose` as separate tool calls.

### Whole screen

For an explicit whole-screen request, or only when target-scoped Cua evidence
cannot bind the requested object:

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/observe.sh" --media --screen
```

The lazy observer keeps a portal-scoped PipeWire stream warm for a short task
burst. Installation/login itself does not open ScreenCast consent.

## `.gwcu`: local truths, not prompt prose

Persistent machine/workspace truth belongs in a single `.gwcu` file, **never in
`AGENTS.md`**.

Scope resolution is deterministic:

```text
GWCU_SCOPE_ROOT override
→ Git worktree root, when inside Git
→ nearest ancestor already containing .gwcu, outside Git
→ current working directory
```

Git repositories are always isolated to their own root truth file. A repo nested
inside a general workspace such as `~/.gwcw/` does **not** inherit
`~/.gwcw/.gwcu`. Outside Git, descendants of `~/.gwcw/` can reuse that workspace
truth file until a more specific non-Git `.gwcu` exists.

When managed truth is enabled in a Git worktree, GWCU adds `/.gwcu` to the root
`.gitignore` **before** creating the file. If it cannot safely establish the
ignore rule, it refuses the persistent write.

`.gwcu` is canonical JSON with schema `gwcu.truths.v1` and explicit sections:

```json
{
  "apps": {},
  "calibration": {},
  "capabilities": {},
  "observed": {},
  "preferences": {},
  "schema": "gwcu.truths.v1"
}
```

- `observed`: low-churn facts directly observed from the environment.
- `capabilities`: compact current capability conclusions.
- `calibration`: stable learned measurements/mappings.
- `preferences`: user-authored behavior preferences; preserve on regeneration.
- `apps`: stable launcher/PWA target identity.

Never persist screenshots, user text, task/conversation history, credentials,
clipboard contents, raw health dumps, transient focus, or transient geometry.
Generated truth stores conclusions, not observation transcripts.

Useful truth controls:

```bash
"$ROOT/scripts/profile.sh" managed on --machine
"$ROOT/scripts/profile.sh" managed off --machine
"$ROOT/scripts/profile.sh" managed status --machine
"$ROOT/scripts/profile.sh" truths status --machine
"$ROOT/scripts/profile.sh" truths scope --machine
"$ROOT/scripts/profile.sh" truths regenerate --machine
```

`GWCU_TRUTHS=off` is the runtime override. The older
`GWCU_PROJECT_MEMORY=off` override remains accepted for compatibility.

A warm exact `.gwcu` app hit skips repeated launcher/PWA resolution. It does not
claim to remove the Cua action itself or the outer route call when routing is
still needed.

## Hermes `/computer-use`

When the Hermes plugin is installed, its native command registry exposes:

```text
/computer-use status
/computer-use managed
/computer-use managed on|off|status
/computer-use truths
/computer-use consent
/computer-use doctor
/computer-use help
```

`managed on` enables persistence and initializes the current scope. `truths`
shows the active `.gwcu` scope/path/counts. `consent` explains and verifies the
RemoteDesktop → EIS/libei contract.

## Latency-first interaction

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
- Consume `.gwcu` before repeating deterministic identity discovery.
- Never retry the same failed delivery shape blindly.
- Never answer a Cua refusal with raw pointer/keyboard injection.

The ideal runtime shape is intentionally boring:

```text
Cua state once → useful action span → next decision boundary
```

## Foreground preservation

Preserve the user's foreground by default. Cua owns exact target activation
through its GNOME integration. If foreground delivery is required, let Cua
activate and verify the exact target. Do not infer foreground need from toolkit
labels such as GTK, Electron, browser, Vulkan, or GLFW.

A structured refusal is capability information, not permission to bypass Cua.

## Pixel-only surfaces

An AT-SPI-empty Vulkan, GLFW, game, canvas, video, or custom-rendered window is
**pixel-only**, not absent.

If Cua resolves the GNOME window, use that target's pixels and compositor
geometry. Do not launch a desktop-wide search because the AX tree is empty.

## Deterministic script surface

The agent-facing helpers are deliberately small:

```bash
# target uncertainty → one route
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"

# host contradiction → one recovery verdict
"$ROOT/scripts/profile.sh" recover --machine

# explicit whole-screen evidence → one observation
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png

# installed-system/truth status
"$ROOT/scripts/computer-use.sh" status
```

Lower-level helpers exist so programs can compose programs without spending
model turns:

```text
app-identity.sh     deterministic launcher/PWA identity
truths.py           .gwcu scope/read/write/regeneration contract
profile.sh read     passive cached session truth
profile.sh refresh  → diagnose.sh → Cua health + GNOME observation health
portal-control.py   RemoteDesktop contract + one-time pointer-only authorization
cua-health.py       thin transport for Cua health_report structuredContent
```

Prefer composed commands above. Call lower-level helpers directly only for
maintenance, testing, or when raw detail is the requested output.

Top-level `ok=true` means the installed system is ready now. `cua-driver doctor
--json` is supplemental diagnostic detail; Cua's stable `health_report` is
upstream control-health truth.

## Cua GNOME integration

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
