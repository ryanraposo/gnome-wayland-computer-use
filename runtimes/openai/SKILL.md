---
name: computer-use
description: Use for Ubuntu GNOME desktop control via Cua Driver.
version: 2.3.0
author: Ryan Raposo
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [computer-use, cua, desktop, automation, gui, gnome, wayland, accessibility]
    category: desktop
    related_skills: [gnome-wayland-reload]
    requires_toolsets: [computer_use]
---

# Computer Use on Ubuntu GNOME

Use **Cua Driver as the only control authority** for the user's actual desktop. WORLDLINE owns transient revisioned truth and postconditions. `.gwcu` owns durable local facts.

> **Resolve exactly. Present exactly. Cua acts. Verify reality.**

## Invocation contract

`/computer-use <task>` is the primary user-facing entry point. Everything after `/computer-use` is normal task text unless the first token is one of these reserved operator subcommands:

`status`, `trace`, `present`, `list-windows`, `cursor-color`, `background`, `managed`, `truths`, `consent`, `doctor`, and `help`.

For a reserved form, your first tool call MUST execute the installed operator surface once; return its result without reinterpretation. These operator/helper surfaces use the terminal tool when it is available; ordinary desktop control does not require terminal access.

```text
/computer-use status
/computer-use trace
/computer-use present --pid PID --window-id ID
/computer-use list-windows [--on-screen-only] [--pid PID]
/computer-use cursor-color [#RRGGBB]
/computer-use background [on|off|status]
/computer-use managed [on|off|status]
/computer-use truths
/computer-use consent
/computer-use doctor
/computer-use help
```

Everything else is a task. `/computer-use open YouTube and play something` means do the task; `open` is not a subcommand.

## Tool/domain boundary

GWCU owns **physical computer use**, not every task that happens to involve a browser or shell.

- If the web is merely an information source — research, retrieval, reading, search, API/web navigation with no dependency on the user's visible browser session — browser/web tools remain free to do that work.
- If the task depends on the user's actual browser session, login, tabs, browser chrome, placement, or visible browser experience, that browser is part of the desktop and Cua owns its actuation.
- Ordinary command-line/shell work belongs to the terminal tool. Use Cua to operate a terminal window only when the user actually wants the terminal manipulated as a visible desktop surface, or the terminal UI itself is the target.
- Terminal availability may unlock GWCU's local operator/helper scripts, but it is not part of the skill's domain and is not required for the skill to be relevant.

A mixed task can cross these boundaries. Using web tooling to research something does not prevent later Cua desktop work, and loading this skill does not claim unrelated web or shell work.

## One actuator, including the user's browser

While this skill is active, **when the task is operating the user's actual browser, do not route browser work through Hermes' separate `browser_*` toolset**. Browser actuation remains Cua work. This restriction does not apply when the web is merely an information source as defined above.

```text
Chromium/Electron exact route available
→ computer_use cua_browser_state / cua_browser_* actions

Firefox, browser chrome, unsupported typed route
→ Cua native window AX/PX route
```

The typed route is admitted by proof:

1. Discover the exact native browser `(pid, window_id)` with Cua `list_windows`.
2. Run the foreground presentation gate when foreground/visible control applies.
3. Bind `cua_browser_state` using both values.
4. Mutate only when the bind says `status:"ok"`, `binding_quality:"exact"`, and `mutation_allowed:true`.
5. Choose the returned opaque `tab_id`; request a fresh `semantic_v2` snapshot.
6. Every mutation invalidates refs. Snapshot again before the next ref-based action and at completion.

Never actuate from a title-only match. Firefox has no typed page-mutation route. An unselected tab may still be fully addressable. Typed page success does not prove the browser window or tab is visibly presented. A hidden/headless/managed browser success is a failure when the requested result is meant to be visible.

## GNOME portal contract

GNOME Wayland is the supported session. **No X11 or XWayland session is required.** Cua uses GNOME `RemoteDesktop` → EIS/libei for input; GNOME may label this permission **Remote Desktop**. GWCU installs no RDP/VNC server or raw-input daemon. ScreenCast/PipeWire is the separate observation path.

Cua's installed `winrects@cua` GNOME Shell helper is part of the supported control plane. Its stable window id is the `window_id` used for exact presentation.

## Core rule

**Observation is an interrupt, not a ritual RPC.**

```text
model decides
→ exact target is established
→ local transaction runs
→ Cua acts
→ WORLDLINE watches postconditions
→ model returns only at a real decision boundary
```

## Control priority

`/computer-use background` controls the **standing delivery preference**. The installer explains this choice and asks once on a fresh install; exact visible takeover remains the default.

- OFF is the default: **exact visible takeover**. GWCU may bring the exact target to the front while acting.
- ON explicitly prefers background delivery where Cua supports it, helping the user keep working in the current foreground window.
- `/computer-use background on` prefers background work.
- `/computer-use background off` restores exact visible takeover.
- `/computer-use background status` reports the current preference; bare `/computer-use background` toggles it.
- Explicit user foreground/background wording wins over the standing preference.
- A requested visible result always finishes with exact visible presentation, even when intermediate work is background.
- Cua runtime truth remains authoritative.

The standing preference applies to otherwise-unspecified Cua native input and GWCU action spans. It is a default, not an interpretation of every task.

There is deliberately **no floating confidence threshold**. Missing foreground words do not imply background intent. Legacy `foreground_confidence` remains parse-compatible and non-authoritative.

The default foreground path is not “send `delivery_mode:foreground` and hope.” Cua documents foreground delivery as action-scoped activation which may restore the prior frontmost window. GWCU therefore makes persistent presentation a separate admission gate.

### Exact default trace

When background priority is OFF, pre-trace this path before the first mutation:

```text
1 DISCOVER
  Cua list_windows
  → exact intended (pid, window_id)
  → no title-only actuation

2 PRESENT
  Cua GNOME presentation gate
  → attested org.cua.WinRects owner
  → exact stable-sequence id + pid exists exactly once
  → Activate(window_id)
  → GNOME reports that exact window focused=true, visible=true, minimized=false
  → otherwise STOP before input

3 ACT
  computer_use mutation against the same pid + window_id
  → delivery_mode="foreground"
  → because the exact target was already frontmost, action-scoped restore returns to it

4 REVALIDATE
  if an action creates/closes/replaces the native target
  → list_windows again before the next focus-bound mutation
  → never carry stale identity forward

5 COMPLETE VISIBLY
  if visible_required
  → present the final exact target again
  → verify focused+visible
  → verify requested app/page state
  → leave it on screen
```

This trace is the default contract, not advice. The Hermes `computer_use` policy shim and `action-span.py` both fail closed before foreground native input when exact `(pid, window_id)` presentation cannot be proved.

For direct Hermes `computer_use` native input, always provide exact integer `pid` and `window_id`. Reads may remain target-free when their schema permits it.

If background was selected and Cua explicitly returns `background_unavailable` / `foreground_required`, the action-span runner may fall forward once. It must pass the same exact presentation gate **before** retrying foreground.

**Control-priority arbitration adds zero model calls.**

## Visible-result contract

Foreground input and persistent presentation are different properties. `delivery_mode:"foreground"` alone does not satisfy “show me”, “watch this”, “take over”, “put this on my screen”, or “leave it open”.

For `visible_required` work:

1. resolve exact native target;
2. present it through `present-window.py` / the policy shim;
3. perform Cua work;
4. re-resolve if native identity changes;
5. present the final exact target again;
6. verify requested state; leave it visible.

Do not use generic compositor guessing or title-only focus as a substitute.

## Call budget

| Situation | setup calls before useful work |
|---|---:|
| known app/window | **0** model calls once exact `(pid, window_id)` is already known; presentation is local |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| local postcondition/revision | **1** — `worldline-capture.sh` |
| explicit whole-screen observation | **1** — `observe.sh` |

## Execution ladder

```text
durable known fact            → .gwcu / current context
current transient fact        → WORLDLINE
web used only as information  → browser/web tooling
ordinary shell/CLI work       → terminal tool
stable recurring mechanics    → repository script (when terminal is available)
one-off mechanical fan-out    → execute_code
predetermined GUI sequence    → one Cua action span
user's browser page work      → exact-bound Cua browser route
user's browser/native fallback→ Cua native AX/PX route
explicit visual uncertainty   → WORLDLINE visual / observe.sh
independent reasoning         → delegate_task
real user choice              → clarify
unresolved desktop conflict   → parent Cua/model loop
```

## Known target

Two or more fully determined actions on the same current evidence **MUST cross the model/tool boundary exactly once**.

When the terminal tool is available, the installed span runner is the preferred local composition surface:

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/computer-use.sh" span --actions-json '{
  "schema":"gwcu.action-span.request.v1",
  "control":{"visible_required":true},
  "actions":[
    {"name":"click","arguments":{"pid":1234,"window_id":88,"x":640,"y":420}},
    {"name":"type_text","arguments":{"pid":1234,"window_id":88,"text":"hello"}},
    {"name":"key_press","arguments":{"pid":1234,"window_id":88,"key":"ENTER"}}
  ]
}'
```

The runner keeps one Cua MCP session open. For every foreground-capable mutation it locally proves exact presentation before sending `tools/call`. Split only when fresh state changes the decision, target identity changes, a branch is undeclared, Cua refuses/fails, or a real user choice appears. Without terminal access, keep using the built-in `computer_use` tool directly and preserve the same decision boundaries.

## WORLDLINE postconditions

Use WORLDLINE when the executor can state what must become true and its local helper surface is available.

```bash
"$ROOT/scripts/worldline-capture.sh" --trigger action:save --expect-json '[{"path":"task.document.saved","op":"eq","value":true}]'
```

Prefer direct truth: AT-SPI, filesystem, process, D-Bus, settings, network and task watchers before pixels. WORLDLINE never injects input. If the local helper cannot be invoked, verify through available `computer_use` evidence instead of treating terminal access as a requirement for desktop control.

## Unknown or browser-backed target

When the local helper surface is available:

```bash
"$ROOT/scripts/profile.sh" route --machine "<target name>"
```

That one route performs the repo/workspace .gwcu lookup before deterministic identity discovery. `.gwcu` accelerates stable identity; live Cua/WORLDLINE truth wins on contradiction. Route discovery does not claim web-only research; use browser/web tooling freely when the web is merely an information source.

## Host contradiction

When the local helper surface is available:

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

Do not make the model perform `read → refresh → diagnose` as separate turns when deterministic recovery is available.

## Whole screen

When the local helper surface is available:

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
"$ROOT/scripts/observe.sh" --media --screen
```

Use visual escalation only when direct evidence is insufficient. Without the helper surface, use the built-in `computer_use` observation path.

## `.gwcu`: durable truth, not runtime state

Persistent machine/workspace truth belongs in one `.gwcu`, **never in `AGENTS.md`**. Never persist screenshots, documents, user text, credentials, transient focus/geometry, or WORLDLINE revisions.

## Failure and refusal policy

**Never answer a Cua refusal with raw pointer/keyboard injection. Never switch silently to Hermes' separate browser toolset while actuating the user's browser. Never guess focus.**

A foreground presentation failure is an actuation boundary: do not send the input. Re-resolve exact identity or report the failure. A background→foreground retry is legal only after Cua explicitly says background delivery is unavailable and the exact presentation gate succeeds.

## Completion proof

```text
direct oracle / WORLDLINE predicate
→ exact Cua target truth
→ focused+visible presentation proof when foreground/visible
→ semantic/page verification
→ pixels only when direct proof is insufficient
```

A task is incomplete when the requested visible result is not actually on the user's desktop.

## Operator surfaces

```bash
/computer-use <task>
/computer-use status
/computer-use trace
/computer-use present --pid PID --window-id ID
/computer-use list-windows [--on-screen-only] [--pid PID]
/computer-use cursor-color [#RRGGBB]
/computer-use background [on|off|status]
/computer-use managed [on|off|status]
/computer-use truths
/computer-use consent
/computer-use doctor
/computer-use help
```

`trace` prints the exact default control path. `present` is the deterministic exact-window presentation primitive. `list-windows` is read-only discovery (no presentation gate, works in both background modes). `cursor-color` sets the agent cursor fill color via Cua WinRects helper (default green, visual aid only). Operator forms require the local helper/terminal surface; their absence does not remove ordinary `computer_use` capability.

## WORLDLINE socket lifecycle

The WORLDLINE daemon runs as a systemd socket-activated user service:

```bash
# Socket path (canonical)
$XDG_RUNTIME_DIR/gnome-wayland-computer-use/worldline.sock

# Service units
gnome-wayland-computer-use-worldline.socket
gnome-wayland-computer-use-worldline.service
```

**Health check RPC:**
```bash
worldline.py request --json '{"op":"status"}'
```

**Recovery commands:**
```bash
systemctl --user restart gnome-wayland-computer-use-worldline.socket gnome-wayland-computer-use-worldline.service
```

**Log inspection:**
```bash
journalctl --user -u gnome-wayland-computer-use-worldline.service -n 50
```

**Socket activation contract:**
- Daemon inherits fd 3 from systemd (`LISTEN_FDS=1`, `LISTEN_PID=$$`)
- `worldline.py listen()` handles this; callers connect to the socket path
- Socket units are installed and enabled by `install.sh`
- Daemon idle timeout defaults to 300s; configurable via `GWCU_WORLDLINE_IDLE_SECONDS`

Project rationale and installation documentation lives in `README.md`.
