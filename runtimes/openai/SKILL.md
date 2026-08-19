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

Use **Cua Driver as the control authority**. WORLDLINE owns transient revisioned facts, invalidation and postconditions. `.gwcu` owns durable repo/workspace truth.

> **The model decides intent. WORLDLINE holds the control loop. Cua executes.**

Cua owns semantic/pixel actions, browser-backed actions, target state, geometry, activation, input delivery, cursor behavior, effects, escalation and structured refusals. WORLDLINE never injects input.

## Invocation contract

`/computer-use <task>` is the primary user-facing entry point. Hermes loads this installed skill and attaches everything after `/computer-use` as the user's instruction. Treat that text exactly like a normal computer-use request; do not parse the first word as an operator command unless it is one of the reserved subcommands below.

Reserved subcommands are `status`, `background`, `managed`, `truths`, `consent`, `doctor`, and `help`. For those forms, invoke the installed operator surface once and return its result:

```text
/computer-use status
/computer-use background [on|off|status]
/computer-use managed [on|off|status]
/computer-use truths
/computer-use consent
/computer-use doctor
/computer-use help
```

Everything else is a task. For example, `/computer-use open YouTube and play something` means perform that task through Cua with this skill loaded; it is not an unknown `open` subcommand.

## One actuator, including the browser

While this skill is active, **do not route browser work through Hermes' separate `browser_*` toolset**. That can create or control a browser surface that is not the user's visible desktop session and violates GWCU's single-actuator contract.

Browser work remains Cua work:

```text
Chromium/Electron exact route available
→ computer_use cua_browser_state / cua_browser_* actions

Firefox, browser chrome, generic GNOME Wayland typed-route refusal,
or any unsupported browser shape
→ normal Cua window discovery + AX/PX computer_use actions
```

Use Cua's browser route only when Cua advertises and successfully binds it. Never infer support from “this is a browser.” A Cua structured refusal is routing truth, not permission to switch to a hidden/headless browser tool.

## GNOME portal contract

GNOME Wayland is the intended session. **No X11 or XWayland session is required.** Cua uses GNOME's `org.freedesktop.portal.RemoteDesktop` API for a local EIS/libei pointer/keyboard session. GNOME may label this permission "Remote Desktop". GWCU installs no RDP/VNC server or raw-input daemon. Whole-screen observation is separately consented through ScreenCast/PipeWire.

## Core rule

**Observation is an interrupt, not a ritual RPC.**

```text
model
→ one local call
→ Cua actions
→ WORLDLINE revisions/predicates
→ continue locally
→ model only at a real decision boundary
```

A model/tool round-trip is justified only when fresh state can change the next decision and local machinery cannot establish it.

## Control priority

`/computer-use background` **toggles the standing delivery preference**.

- OFF is the default: foreground/obvious control.
- ON prefers background delivery where Cua supports it.
- Explicit user foreground/background wording overrides the standing preference.
- A task whose requested result must remain visible forces foreground presentation.
- Cua capability/runtime truth has final say.

There is deliberately **no floating confidence threshold** in the control policy. Absence of words such as “foreground” is not evidence for background use. Legacy `foreground_confidence` metadata is accepted by the runner for compatibility but does not select delivery.

When preparing a GWCU action span, pass only control facts that are actually known:

```json
{"control":{"visible_required":true}}
```

or, when the user explicitly chose a delivery shape:

```json
{"control":{"explicit_mode":"background"}}
```

The local arbiter is mechanical:

```text
visible result required                    → foreground
explicit foreground/background wording    → explicit mode
otherwise                                 → standing preference
Cua capability/runtime truth              → final say
```

`visible_required` is stronger than transient foreground input. It means the completed task must be left on the user's visible desktop. Phrases such as “show me,” “watch/play this,” “take control,” “put this on my screen,” or “leave it open” normally imply it.

For ordinary input, set `delivery_mode` explicitly when calling Hermes `computer_use`. The bundled GWCU Hermes policy shim also fills an omitted delivery mode from the standing preference when the user has granted its documented `tools.override` capability. This is a backstop, not a replacement for expressing known intent.

If background was selected but Cua returns `background_unavailable` / `foreground_required`, the local action-span runner retries that action once with foreground when Cua's live tool schema supports `delivery_mode`. It reports the override; it does not ask another model to rediscover the same fact.

**Control-priority arbitration itself adds zero model calls.**

## Visible-result contract

Foreground delivery and visible presentation are separate properties.

A Cua foreground action may temporarily front a target and restore the previous app. That is correct delivery but does **not** satisfy “show me,” “watch this,” or another visible-result request.

For `visible_required` tasks:

1. Resolve the exact native target through Cua.
2. Perform the work through Cua.
3. Persistently present the exact target with Cua (`focus_app` with `raise_window:true`, or Cua `bring_to_front` when using the direct MCP/action-span surface).
4. Verify the intended target is the presented window and the requested state is true.
5. Leave it visible unless the user asked for a different final presentation.

A hidden/headless/managed browser success is a failure of this contract even when page state changed correctly.

## Call budget

| Situation | setup calls before useful work |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| local postcondition/revision | **1** — `worldline-capture.sh` |
| explicit whole-screen observation | **1** — `observe.sh` |

## Execution ladder

```text
durable known fact            → .gwcu / current context
current transient fact        → WORLDLINE
stable recurring mechanics    → repository script
one-off mechanical fan-out    → execute_code
predetermined GUI sequence    → one Cua action span
browser page work             → Cua browser route if Cua binds it exactly
browser/native fallback       → Cua window AX/PX route
explicit visual uncertainty   → WORLDLINE visual / observe.sh
independent reasoning         → delegate_task
real user choice              → clarify
unresolved desktop conflict   → parent Cua/model loop
```

Keep portal consent and user-facing desktop decisions in the parent session. Delegate independent reasoning, not the interactive control loop.

## Known target

If two or more consecutive Cua actions are fully determined by the same current evidence, they **MUST cross the model/tool boundary exactly once**.

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/computer-use.sh" span --actions-json '{
  "schema":"gwcu.action-span.request.v1",
  "control":{"visible_required":true},
  "actions":[
    {"name":"click","arguments":{"x":640,"y":420}},
    {"name":"type_text","arguments":{"text":"hello"}},
    {"name":"key_press","arguments":{"key":"ENTER"}}
  ]
}'
```

The installed runner keeps one Cua MCP session open. Split only when fresh state changes the next action, target identity becomes stale, a branch is undeclared, an async transition lacks a sufficient predicate, Cua fails/refuses, or a real user choice is required. No ritual screenshot or fixed sleep belongs between decided actions.

## WORLDLINE postconditions

Use WORLDLINE when the executor can state what must become true.

```bash
"$ROOT/scripts/worldline-capture.sh" --trigger action:save --expect-json '[{"path":"task.document.saved","op":"eq","value":true}]'
```

Events may push authoritative facts. Prefer AT-SPI, filesystem, process, D-Bus, gsettings, network and task watchers before pixels. WORLDLINE runtime state is transient under `$XDG_RUNTIME_DIR`.

## Unknown or browser-backed target

```bash
"$ROOT/scripts/profile.sh" route --machine "<target name>"
```

Inside that one call: repo/workspace `.gwcu` lookup → deterministic launcher/PWA resolver only on miss → optional stable writeback → `gwcu.route.v1`. `.gwcu` accelerates identity; live Cua/WORLDLINE state wins on contradiction.

This route identifies the desktop target. It never authorizes a switch to Hermes' separate browser automation plane.

## Host contradiction

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

Do not make the model perform `read → refresh → diagnose` separately.

## Whole screen

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/observe.sh" --media --screen
```

The observer keeps a portal-scoped PipeWire stream warm for a short task burst. Installation does not open ScreenCast merely to preheat it.

## `.gwcu`: durable truth, not runtime state

Persistent machine/workspace truth belongs in a single `.gwcu` file, **never in `AGENTS.md`**. Git scopes add `/.gwcu` to the root `.gitignore` before the first write. Never persist screenshots, documents, user text, credentials, task history, transient focus/geometry, presentation guesses, or WORLDLINE revisions/predicates.

## Failure and refusal policy

Treat Cua output as information. **Never retry the same failed delivery shape blindly. Never answer a Cua refusal with raw pointer/keyboard injection. Never answer it by silently changing to Hermes' separate browser toolset.** A background→foreground retry is legal only when Cua explicitly establishes that the background delivery shape is unavailable and foreground is the declared deterministic fallback.

Do not bypass Cua with `ydotool`, `/dev/uinput`, guessed focus or another control daemon.

## Completion proof

```text
direct oracle / WORLDLINE predicate
→ Cua verification
→ targeted semantic evidence
→ visual evidence only when necessary
→ visible-target verification when visible_required
```

Do not add a screenshot merely to feel certain. Do not report completion from a surface the user cannot see when visibility is part of the requested result. Report real failures and unresolved conflicts.

## Operator surfaces

```bash
/computer-use <task>
/computer-use status
/computer-use background [on|off|status]
/computer-use consent
/computer-use managed on|off|status
/computer-use truths
/computer-use doctor
```

Human-facing architecture, lifecycle and operator documentation lives in `README.md`.
