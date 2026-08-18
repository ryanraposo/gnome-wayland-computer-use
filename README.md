# gnome-wayland-computer-use

**An OS model for computer use on Ubuntu 26.04 GNOME Wayland.**

GWCU turns computer use into execution over a known machine. The model supplies intent and handles genuine decisions; local machinery carries everything already determined.

> **Information over deliberation. Model calls at decision boundaries.**
>
> **Cua controls. WORLDLINE knows. `.gwcu` remembers.**

- **Cua Driver** is the sole desktop control authority.
- **WORLDLINE** maintains transient, revisioned machine state and postconditions.
- **`.gwcu`** preserves durable repo/workspace truth across sessions.
- **ScreenCast/PipeWire** is an escalation sensor, not the observation loop.

```text
                intent / contingent plan
                         │
                         ▼
                   ┌───────────┐
                   │ WORLDLINE │──── conflict ────→ model
                   └─────┬─────┘
              expected   │
                         ▼
                  Cua action span
                         │
                         ▼
              GNOME RemoteDesktop
                   EIS / libei
                         │
                         ▼
                      desktop
                    ┌────┴────┐
                    ▼         ▼
                 AT-SPI    visual sensor
              direct truth  when needed
                    └────┬────┘
                         ▼
                 next WORLDLINE
                     revision
```

**Observation is an interrupt, not a ritual RPC.**

## The inversion

Ordinary computer-use loops repeatedly pay the model to discover that expected things happened:

```text
observe → model → click → observe → model → type → observe → model → …
```

GWCU preserves information until evidence invalidates it:

```text
model decides
→ Cua executes the determined span
→ WORLDLINE observes machine evidence
→ expected postcondition true
→ continue locally
→ model only when the next decision changed
```

A click does not erase the known machine. WORLDLINE revises affected facts, preserves unrelated ones, and can establish outcomes from AT-SPI, process/filesystem state, settings, network/task events, or visual evidence when pixels are genuinely required.

```text
click Save
→ document.dirty == false
→ predicate satisfied
→ continue

No screenshot. No model turn.
```

WORLDLINE is not an agent and not a competing computer-use implementation. It is the continuity layer between model decisions and Cua execution. See [WORLDLINE.md](WORLDLINE.md).

## Authority

Cua Driver owns semantic/pixel targeting, geometry, activation, pointer and keyboard delivery, verification, effects and structured refusals. GWCU never bypasses Cua with `ydotool`, `/dev/uinput`, guessed focus, or a second control daemon.

On GNOME Wayland, Cua uses the compositor-approved Remote Desktop portal to obtain its EIS/libei input session. GNOME may label this permission **Remote Desktop** or **remote control**; GWCU does not install a remote-login service.

**No X11 or XWayland session is required.**

## What execution feels like

### Known target

```text
known target
→ one already-decided Cua span
→ WORLDLINE waits on postconditions
→ continue locally
→ model at the next real decision boundary
```

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"

"$ROOT/scripts/computer-use.sh" span --actions-json '{
  "schema":"gwcu.action-span.request.v1",
  "actions":[
    {"name":"click","arguments":{"x":640,"y":420}},
    {"name":"type_text","arguments":{"text":"hello"}},
    {"name":"key_press","arguments":{"key":"ENTER"}}
  ]
}'
```

Two or more consecutive Cua actions determined by the same evidence cross the model/tool boundary once.

### Wait on reality

```bash
"$ROOT/scripts/worldline-capture.sh" \
  --trigger action:save \
  --expect-json '[
    {"path":"settings.color_scheme","op":"eq","value":"prefer-dark"}
  ]'
```

Task-specific watchers can push authoritative events into WORLDLINE, so a transaction can wait on `task.download.foo_zip == true` instead of staring at a browser.

### Unknown app or PWA

```bash
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"
```

One local call resolves stable launcher/PWA identity. With managed truth enabled, reusable identity can be written to `.gwcu`, avoiding future rediscovery.

### Host contradiction

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

One recovery call owns the local diagnostic fan-out, including WORLDLINE health.

### Visual uncertainty

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
```

The observer is socket-activated and keeps ScreenCast/PipeWire warm for a short task burst. WORLDLINE requests it only when semantic/direct evidence is insufficient. Cold ScreenCast session/consent establishment has its own longer timeout; once the stream exists, fresh-frame latency keeps the short capture budget.

## MCP

GWCU maps cleanly onto MCP without making MCP part of the control plane.

A thin MCP adapter can expose coarse deterministic operations such as **execute a Cua span**, **capture/wait on a WORLDLINE revision**, **route a target**, **recover the host**, and **request visual evidence**. WORLDLINE state can be exposed as read-only resources where useful. The model should see meaningful operations and compact results, not every internal sensor event.

```text
MCP / agent runtime     invocation boundary
GWCU                    OS model + deterministic composition
Cua Driver              desktop authority
GNOME                    machine
```

The local scripts remain the canonical mechanics. MCP is an interoperable front door, not a second implementation.

## `.gwcu`: durable truth

WORLDLINE state is transient. `.gwcu` is durable.

`.gwcu` stores low-churn facts such as stable app identity, capability conclusions, calibration and user-authored preferences. It never stores screenshots, task history, transient focus, documents, credentials or WORLDLINE revisions.

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

Scope is deterministic:

```text
GWCU_SCOPE_ROOT override
→ Git worktree root
→ nearest non-Git ancestor already containing .gwcu
→ current directory
```

Git is an explicit installation dependency. For Git worktrees, managed mode writes `/.gwcu` to the root `.gitignore` **before** creating `.gwcu`. See [GWCU.md](GWCU.md).

## Installation

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

The installer qualifies Ubuntu 26.04 GNOME Wayland; repairs the portal/PipeWire/AT-SPI/Python GI/Git foundation; installs or qualifies pinned Cua Driver; records Cua ownership immediately; installs the Cua GNOME helper; retires exact legacy GWCU `ydotoold` and uinput artifacts during upgrades; establishes persistent RemoteDesktop consent; deploys the portable Agent Skill metadata plus optional Hermes integration; configures managed `.gwcu`; installs socket-activated WORLDLINE/observer services; and verifies Cua + WORLDLINE health.

When Hermes is present the installer asks before wiring the `/computer-use` integration and asks managed-truth and background-priority preferences. The `computer-use` skill is always replaced with the GWCU skill (the previous copy is archived and restored by teardown); stale duplicate Hermes plugins are retired so the project's `/computer-use` is the one that runs. The installer finishes by printing the uninstall and teardown commands.

The first explicit whole-screen capture may still require separate ScreenCast consent.

```bash
/computer-use status
/computer-use consent
/computer-use managed status
/computer-use truths
/computer-use doctor
```

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

The curl-pipe entry point only trusts an adjacent teardown when the uninstaller itself is a real file; stdin execution cannot resolve scripts from the caller's working directory. Teardown removes only skill/plugin directories carrying GWCU's managed marker — including every GWCU-owned Hermes plugin copy so a stale duplicate cannot keep `/computer-use` registered — restores archived components safely, and preserves repo/workspace `.gwcu` files. Cua is preserved by default; `--remove-cua` uses durable provisioning ownership, while `--purge-cua` is an explicit full purge.

## Design rules

- Cua changes the desktop.
- WORLDLINE explains what changed and what remains valid.
- Direct truth beats visual inference.
- Predicates replace ritual re-observation.
- Determined mechanics stay inside one local call.
- `.gwcu` contains durable truth, never prompt prose.
- A real conflict returns control to the model.
- Install and teardown mutate only state they can prove they own.

See [DETERMINISM.md](DETERMINISM.md) for the constitution, [CAPABILITIES.md](CAPABILITIES.md) for runtime boundaries, and [PERF_NOTES.md](PERF_NOTES.md) for latency/call economics.
