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
keeps whole-screen observation independent, and converts recurring desktop
reasoning into deterministic local information.

> **The model decides intent. Programs collapse mechanics. Cua executes.**

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

Spend a model/tool boundary only when it can change the next action.

| Situation | GWCU setup calls before useful work |
|---|---:|
| known app/window | **0** |
| uncertain app identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen observation | **1** — `observe.sh` |

A known target goes directly to Cua. Do not ceremonially preflight the host.

## Workflow Contract

Take control and do the requested work. Ask only when target, outcome, or
authorization is materially ambiguous. For a terminal/admin task, use the
terminal directly.

Keep normal computer use target-scoped. Diagnostics, update checks, host
inventories, and whole-screen capture stay off the success path unless returned
evidence genuinely requires them.

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

The call composes, inside one shell process:

```text
project AGENTS truth lookup
→ launcher/PWA resolver only on miss
→ stable truth write-back only on confident resolution
→ gwcu.route.v1
```

`gwcu.route.v1` returns one of:

```text
target_resolved  → Cua target state with identity evidence
live_target      → no stable launcher truth; ask Cua for live target state
target_ambiguous → disambiguate only the returned candidates
```

Do not separately call `app-identity.sh`, `profile.sh read`, and app/window
enumeration when this one route call answers the uncertainty.

### Project-local stable memory

When `profile.sh route` confidently resolves a launcher identity inside a Git
worktree, it maintains a bounded block in the project-root `AGENTS.md`:

```text
<!-- gwcu:desktop-truths:v1:start -->
## GWCU desktop truths
...
<!-- gwcu:app:v1 {compact JSON stable identity} -->
<!-- gwcu:desktop-truths:v1:end -->
```

The block is deliberately boring and regex-addressable. It stores only
low-churn routing facts such as desktop ID, app ID, StartupWMClass, app kind, and
display name. It stores no timestamps, screenshots, task history, user text, or
volatile window geometry. Entries are capped and updated in place.

The next route consults this block **before** scanning launchers. Live Cua state
wins whenever remembered identity contradicts the desktop. Set
`GWCU_PROJECT_MEMORY=off` to disable project write-back; set `GWCU_PROJECT_ROOT`
only for controlled tooling/tests.

### Host contradiction

If a result contradicts installed/runtime state, make **one recovery call**:

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

That command reads cached session truth and, only when stale or missing,
refreshes through `diagnose.sh` inside the same invocation. It returns
`host_ready` or `host_recovery` plus one deterministic `next` action.

Do not make the model perform `read → refresh → diagnose` as separate calls.

### Whole screen

For an explicit whole-screen/desktop request, or only when target-scoped Cua
evidence cannot bind the requested object:

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/observe.sh" --media --screen
```

The lazy observer keeps a portal-scoped PipeWire stream warm for a bounded task
burst. Installation/login itself does not open capture consent.

## Hermes Native Orchestration

When Hermes exposes these tools, use its UI and orchestration primitives rather
than reproducing them in prose or serial turns.

### Clarification is a UI surface

When a genuine user decision blocks progress, call `clarify` instead of writing
a numbered question in chat. Put up to four selectable choices in `choices`,
best recommendation first; Hermes marks that first choice as recommended. Use
`multi_select=true` when several choices may apply. Keep low-stakes reversible
decisions agent-owned.

Do not delegate a subtask that may need clarification: delegated workers cannot
ask the user. Keep portal consent, authorization, and interactive desktop
decisions in the parent session.

### Program mechanical fan-out

For a one-off task that needs 3+ terminal/file/web tool calls with deterministic
branching, filtering, or loops, prefer Hermes `execute_code` so those calls and
intermediate results occur inside one model turn. Keep **recurrent computer-use
mechanics in tested GWCU scripts**; task-specific programmatic composition belongs
in `execute_code`.

`execute_code` is not a substitute for Cua's `computer_use` loop. Use it for the
surrounding mechanical work its sandbox actually exposes.

### Delegate reasoning, not mechanics

Use `delegate_task` for independent research/reasoning or context-heavy work
that can return a compact summary. Batch independent subtasks when useful. If
Hermes supports async delivery for the current session and the desktop work can
continue independently, use `background=true`; the consolidated result can
re-enter the parent conversation when complete.

Do not delegate trivial tool calls, deterministic sequences a script can own, or
interactive desktop steps. The parent owns user-facing decisions and Cua action
state.

### Let bounded processes finish asynchronously

For bounded builds/tests/deploy-like shell work that can run beside desktop
interaction, use Hermes terminal `background=true, notify_on_complete=true`.
Use silent background only for genuinely long-lived servers/watchers, then
verify readiness explicitly. Never shell-background with `&`, `nohup`, or
`setsid` when Hermes can track the process.

The hierarchy is:

```text
stable recurring mechanics → repository script
one-off mechanical fan-out → execute_code
independent reasoning       → delegate_task
bounded long process        → terminal background + completion notification
real user choice            → clarify
interactive desktop action  → parent Cua loop
```

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
- Reuse project AGENTS identity truth until live evidence contradicts it.
- Never retry the same failed delivery shape blindly.
- Never answer a Cua refusal with raw pointer/keyboard injection.

Ideal shape:

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
# uncertainty → memory lookup + resolution + optional write-back
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"

# host contradiction → one recovery verdict
"$ROOT/scripts/profile.sh" recover --machine

# explicit whole-screen evidence → one observation
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
```

Lower-level helpers exist so programs can compose hard sequences without
spending model turns:

```text
app-identity.sh    deterministic launcher/PWA identity
profile.sh read    passive cached session truth
profile.sh refresh → diagnose.sh → Cua health + GNOME observation health
cua-health.py      thin transport for Cua health_report structuredContent
```

Prefer composed commands. Call lower-level helpers directly only for
maintenance, testing, or when their raw detail is the requested output.

Top-level `ok=true` means the installed system is ready now. `cua-driver doctor
--json` is supplemental detail; Cua's stable `health_report` is upstream
control-health truth.

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