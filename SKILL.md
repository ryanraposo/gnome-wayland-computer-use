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

Use **Cua Driver as the control authority**.

GWCU adds two things around it:

- **WORLDLINE** — transient revisioned facts, invalidation and postconditions.
- **`.gwcu`** — durable repo/workspace truth worth reusing later.

> **The model decides intent. WORLDLINE holds the control loop. Cua executes.**

Cua owns semantic and pixel actions, target/window state, GNOME geometry,
verified activation, input delivery, cursor behavior, effects, escalation and
structured refusals.

WORLDLINE never injects input. It watches current state and wakes deterministic
work when declared predicates become true.

## GNOME portal contract

GNOME Wayland is the intended session. **No X11 or XWayland session is required.**

Cua uses GNOME's `org.freedesktop.portal.RemoteDesktop` API to obtain a local
pointer/keyboard EIS/libei session. The installer normally establishes this
one-time permission before declaring the machine ready.

GNOME may label the permission "Remote Desktop" or "remote control"; GWCU does
not install an RDP/VNC server, raw-input daemon or project input udev rule.

Whole-screen observation is separate: the observer uses ScreenCast/PipeWire and
may have its own consent.

## Core rule

**Observation is an interrupt, not a ritual RPC.**

Do not assume every action invalidates every fact.

When an action sequence and its postconditions are already determined:

```text
model
→ one local call
→ Cua actions
→ WORLDLINE revisions/predicates
→ continue locally
→ model only at a real decision boundary
```

A model/tool round-trip is justified only when fresh state can actually change
the next decision and the local runtime cannot establish it.

## Call budget

| Situation | setup calls before useful work |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| local postcondition/revision | **1** — `worldline-capture.sh` |
| explicit whole-screen observation | **1** — `observe.sh` |

The WORLDLINE call is local deterministic machinery. It should replace repeated
model-visible observation, not add ceremony to every action.

## Execution ladder

Choose the cheapest sufficient mechanism:

```text
durable known fact            → .gwcu / current context
current transient fact        → WORLDLINE
stable recurring mechanics    → repository script
one-off mechanical fan-out    → execute_code
predetermined GUI sequence    → one Cua action span
explicit visual uncertainty   → WORLDLINE visual / observe.sh
independent reasoning         → delegate_task
real user choice              → clarify
unresolved desktop conflict   → parent Cua/model loop
```

Keep portal consent and user-facing desktop decisions in the parent session.
Delegate independent reasoning, not the interactive control loop.

## Known target

Start with useful Cua state. Use a grounded semantic element when one exists;
otherwise use pixels from the same target state.

If two or more consecutive Cua actions are fully determined by the same current
evidence, they **MUST cross the model/tool boundary exactly once**.

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

The installed runner keeps one Cua MCP session open for the already-decided
sequence and stops at the first Cua failure/refusal/transport boundary.

Split a span only when:

- fresh returned/rendered state can change the next action or its arguments;
- navigation/dialog/target disappearance invalidates remaining evidence;
- an async transition has no sufficient completion predicate;
- Cua reports failure, refusal or ambiguity requiring a new strategy;
- new authorization or a real user choice is required.

Otherwise keep going. No ritual screenshot or fixed sleep belongs between
already-decided actions.

## WORLDLINE postconditions

Use WORLDLINE when the executor can state what must become true.

```bash
"$ROOT/scripts/worldline-capture.sh" \
  --trigger action:save \
  --expect-json '[
    {"path":"task.document.saved","op":"eq","value":true}
  ]'
```

A capture seals one local revision from queued events/direct oracles and
evaluates the predicates.

Event sources can contribute authoritative facts:

```bash
python3 "$ROOT/scripts/worldline.py" request --json '{
  "op":"event",
  "event":{
    "source":"task",
    "type":"download-complete",
    "facts":{"task.download.foo_zip":true},
    "invalidates":["ui.downloads"]
  }
}'
```

Prefer direct evidence to pixels:

```text
AT-SPI
filesystem
process
D-Bus
gsettings
network
task watcher
```

Use visual evidence only when those cannot answer the question:

```bash
"$ROOT/scripts/worldline-capture.sh" --trigger visual:needed --visual
```

WORLDLINE runtime state is transient and lives under `$XDG_RUNTIME_DIR`.

## Unknown or browser-backed target

Make one local routing call:

```bash
"$ROOT/scripts/profile.sh" route --machine "<target name>"
```

Inside that call:

```text
repo/workspace .gwcu lookup
→ deterministic launcher/PWA resolver only on miss
→ optional stable writeback
→ gwcu.route.v1
```

`.gwcu` accelerates identity. It is never control authority.

**Live Cua/WORLDLINE state wins on contradiction.**

## Host contradiction

If evidence contradicts the installed/runtime state:

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

Do not make the model perform `read → refresh → diagnose` separately.

## Whole screen

For an explicit whole-screen request, or when target-scoped/direct evidence
cannot bind the requested object:

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/observe.sh" --media --screen
```

The observer keeps a portal-scoped PipeWire stream warm for a short task burst.
Installation does not open ScreenCast merely to preheat it.

## `.gwcu`: durable truth, not runtime state

Persistent machine/workspace truth belongs in a single `.gwcu` file, **never in
`AGENTS.md`**.

Scope:

```text
GWCU_SCOPE_ROOT override
→ Git worktree root
→ nearest ancestor already containing .gwcu outside Git
→ current working directory
```

Git repositories are isolated to their own root truth file. Managed Git truth
adds `/.gwcu` to the root `.gitignore` before the first write.

Schema:

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

Never persist screenshots, documents, user text, credentials, task history,
transient focus/geometry, or WORLDLINE revisions/predicates.

## Failure and refusal policy

Treat Cua output as information.

**Never retry the same failed delivery shape blindly.**

**Never answer a Cua refusal with raw pointer/keyboard injection.**

If Cua refuses or fails:

1. consume its structured reason/evidence;
2. invalidate assumptions that reason contradicts;
3. use a different Cua-supported strategy only when justified;
4. return to reasoning when no declared branch applies.

Do not bypass the authority boundary with `ydotool`, `/dev/uinput`, guessed
focus or an alternate control daemon.

## Completion proof

A task is complete when the requested outcome is established by the cheapest
sufficient evidence:

```text
direct oracle / WORLDLINE predicate
→ Cua verification
→ targeted semantic evidence
→ visual evidence only when necessary
```

Do not add a screenshot merely to feel certain.

Report real failures and unresolved conflicts. Do not manufacture success from
an unchanged screen or a stale durable fact.

## Operator surfaces

```bash
/computer-use status
/computer-use consent
/computer-use managed on|off|status
/computer-use truths
/computer-use doctor
```

Runtime files of interest:

```text
scripts/computer-use.sh
scripts/action-span.py
scripts/worldline.py
scripts/worldline-capture.sh
scripts/observer.py
scripts/observe.sh
scripts/profile.sh
scripts/truths.py
```

The architecture source of truth is `WORLDLINE.md`; durable truth is specified
in `GWCU.md`; hard behavioral rules are in `DETERMINISM.md`.
