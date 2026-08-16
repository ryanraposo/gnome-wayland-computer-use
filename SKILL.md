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

Cua owns semantic/pixel actions, target state, geometry, activation, input delivery, cursor behavior, effects, escalation and structured refusals. WORLDLINE never injects input.

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

`/computer-use background` **toggles priority for background computer use**. `background on|off|status` is available for deterministic scripting.

- OFF is the default: obvious control, the fastest and most deterministic GNOME Wayland path.
- ON prefers background delivery where Cua supports it. Background is a priority, not a promise.

Resolve presentation **inside the same reasoning pass that already understands the user's task. Never add a model call just to classify foreground/background.** When preparing a GWCU action span, include one tiny piece of already-known intent metadata:

```json
"control": {"foreground_confidence": 0.82}
```

`foreground_confidence` means confidence that satisfying the user's intent inherently benefits from or requires visible foreground control. It is not general task confidence.

The local arbiter is mechanical:

```text
explicit foreground/background wording → wins
F < 0.40                              → background
0.40 ≤ F ≤ 0.60                       → standing toggle wins
F > 0.60                              → foreground
Cua capability/runtime truth          → final say
```

If the resolved mode is foreground while background priority is ON, tell the user in the same response that begins execution: **“Doing that now — switching to foreground. OK?”** This is a lightweight heads-up/yield opportunity, not another preflight model call. A user objection stops continuation.

If background was selected but Cua returns `background_unavailable` / `foreground_required`, the local action-span runner retries that action once with foreground when Cua's live tool schema supports `delivery_mode`. It reports the override; it does not ask another model to rediscover the same fact.

The runner queries Cua's live MCP tool schemas and injects `delivery_mode` only for tools that actually advertise it. Never invent unsupported Cua arguments, a second cursor, overlay, input backend, or hidden-control route. Cua owns cursor presentation and actuation.

**Control-priority arbitration itself must add zero model calls.**

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
  "control":{"foreground_confidence":0.82},
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

Inside that one call: repo/workspace .gwcu lookup → deterministic launcher/PWA resolver only on miss → optional stable writeback → `gwcu.route.v1`. `.gwcu` accelerates identity; live Cua/WORLDLINE state wins on contradiction.

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

Persistent machine/workspace truth belongs in a single `.gwcu` file, **never in `AGENTS.md`**. Git scopes add `/.gwcu` to the root `.gitignore` before the first write. Never persist screenshots, documents, user text, credentials, task history, transient focus/geometry, foreground-confidence guesses, or WORLDLINE revisions/predicates.

## Failure and refusal policy

Treat Cua output as information. **Never retry the same failed delivery shape blindly. Never answer a Cua refusal with raw pointer/keyboard injection.** A background→foreground retry is legal only when Cua explicitly establishes that the background delivery shape is unavailable and foreground is the declared deterministic fallback.

Do not bypass Cua with `ydotool`, `/dev/uinput`, guessed focus or another control daemon.

## Completion proof

```text
direct oracle / WORLDLINE predicate
→ Cua verification
→ targeted semantic evidence
→ visual evidence only when necessary
```

Do not add a screenshot merely to feel certain. Report real failures and unresolved conflicts.

## Operator surfaces

```bash
/computer-use status
/computer-use background [on|off|status]
/computer-use consent
/computer-use managed on|off|status
/computer-use truths
/computer-use doctor
```

The architecture source of truth is `WORLDLINE.md`; durable truth is specified in `GWCU.md`; hard behavioral rules are in `DETERMINISM.md`.
