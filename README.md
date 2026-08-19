```text
                          ▄  ▄▄  ▄▄▄▄
                             ▄▀ 0x0 ▀▄
                              █  ───  █
                              █  ███  █
                               ▀▀   ▀▀
```

# gnome-wayland-computer-use

Agents have variable success using Linux. GWCU makes computer use dependable on Ubuntu 26 GNOME Wayland by putting one desktop actuator behind a small local world model.

[Install](#install) · [Use it](#use-it) · [Control](#control) · [Why WORLDLINE exists](#why-worldline-exists) · [`.gwcu`](#gwcu) · [Invariants](#invariants)

---

**Cua controls. WORLDLINE knows. `.gwcu` remembers.**

```text
model decides
→ Cua acts
→ WORLDLINE revises what changed
→ expected postcondition becomes true
→ continue locally
→ model re-enters only when reality creates a new decision
```

Observation is an interrupt, not a ritual RPC. Facts are valid until invalidated.

## What it is

| Layer | Job |
|---|---|
| **Cua Driver** | The only desktop actuator: native windows, browser-backed surfaces, pointer/keyboard, semantics, pixels and verification. |
| **WORLDLINE** | Transient revisioned state, invalidation, predicates, waits, branches and conflicts. |
| **`.gwcu`** | Durable repo/workspace truth worth reusing in another session. |

On GNOME Wayland, Cua uses `org.freedesktop.portal.RemoteDesktop` → EIS/libei for compositor-approved local input. GNOME may label that permission **Remote Desktop** or **remote control**. GWCU installs no RDP/VNC server and no raw-input daemon.

**No X11 or XWayland session is required.**

## Use it

With Hermes, the installed skill owns the native slash command:

```text
/computer-use open YouTube and play something
/computer-use rename this file and put it in Downloads
/computer-use send the message I drafted
```

Everything after `/computer-use` is a task except these reserved operator subcommands:

```text
/computer-use status
/computer-use background [on|off|status]
/computer-use managed [on|off|status]
/computer-use truths
/computer-use consent
/computer-use doctor
/computer-use help
```

### Browser work is still computer use

`/computer-use` does not jump to Hermes' separate browser automation plane. Cua remains the actuator.

- Where Cua can bind an exact supported Chromium/Electron page route, GWCU uses Cua's typed browser actions.
- Firefox, browser chrome, and browser shapes Cua cannot bind exactly stay on Cua's ordinary native AX/PX window route.
- A Cua refusal is reported or escalated inside Cua's supported ladder. It is never permission to disappear into a headless/managed browser.

This matters because page success and desktop success are different things. If the request is “show me,” “watch this,” or otherwise requires a visible result, the final target must actually be on the user's desktop.

## Control

`/computer-use background` toggles the standing delivery preference:

```text
OFF  → foreground / obvious control (default, fastest, most deterministic)
ON   → background where Cua can deliver it safely
```

The policy is intentionally boring:

```text
explicit foreground/background request  → wins
visible-result request                   → foreground presentation
otherwise                                → standing preference
Cua capability/runtime truth             → final say
```

There is no confidence-score threshold. Missing foreground words do not mean “background.”

GWCU's Hermes plugin can, with Hermes' explicit `tools.override` capability consent, wrap the built-in `computer_use` tool so omitted native-input `delivery_mode` values inherit the saved GWCU preference mechanically. The skill still owns `/computer-use`; the plugin does not register a competing slash command.

### Visible is a postcondition

Foreground delivery may briefly front a window and then restore whatever was previously focused. That is useful for unobtrusive automation, but it does not satisfy a request to leave something visible.

For a visible-result task GWCU resolves the exact Cua target, performs the work, presents that target persistently, verifies the requested state, and leaves it visible.

## Why WORLDLINE exists

Ordinary GUI automation repeatedly pays the model to rediscover expected outcomes:

```text
observe → model → click → observe → model → type → observe → model
```

GWCU keeps already-known mechanics local:

```text
click Save
→ document.dirty == false
→ predicate satisfied
→ continue
```

WORLDLINE can ingest authoritative facts from AT-SPI, filesystem/process state, D-Bus, settings, network/task watchers and, only when needed, visual evidence. Revisions invalidate affected dependencies while unrelated facts survive.

WORLDLINE never injects input. A real conflict or undeclared branch returns control to the model.

## `.gwcu`

`.gwcu` stores low-churn local truth such as app identity, capability conclusions, calibration and user-authored preferences.

It never stores screenshots, documents, credentials, task history, transient focus/geometry, presentation guesses or WORLDLINE revisions.

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

For Git worktrees, managed mode writes `/.gwcu` to the root `.gitignore` before creating the truth file. Live Cua/WORLDLINE evidence wins over cached truth on contradiction.

## Install

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

The installer qualifies Ubuntu 26.04 GNOME Wayland, repairs Git/portal/PipeWire/AT-SPI/Python-GI dependencies, installs or reuses pinned Cua Driver `0.20.0` plus its GNOME helper, establishes RemoteDesktop consent, deploys the Agent Skill and optional Hermes policy integration, configures `.gwcu` and background priority, enables WORLDLINE plus the lazy visual observer, retires provably old GWCU control artifacts, and verifies Cua + WORLDLINE health before claiming success.

Run it as the logged-in desktop user, not by wrapping the installer in `sudo`.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Teardown removes only GWCU-owned integration and transient runtime state. Repo/workspace `.gwcu` content survives. Cua is preserved by default; `--remove-cua` removes only a GWCU-provisioned installation, while `--purge-cua` is the explicit full purge.

## Invariants

- **Cua is the only actuator.** Native apps and browser work share one control authority.
- **Visible requests end visibly.** Hidden/headless success is not completion when presentation is part of the task.
- **Background OFF means foreground by default.** Missing intent metadata cannot silently reverse it.
- **WORLDLINE is read-only knowledge machinery.** Events and predicates do not gain input authority.
- **Postconditions replace ritual observation.** Model calls happen at decision boundaries.
- **`.gwcu` is durable only.** Runtime state stays transient.
- **Direct truth beats pixels.** Visual evidence is escalation, not ceremony.

## Project map

```text
SKILL.md                 runtime behavior contract
AGENTS.md                repository / installation instructions for agents
scripts/action-span.py   one-session Cua spans + mechanical control policy
scripts/worldline.py     revision store, predicates, waits, conflicts
scripts/profile.sh       app routing, truth composition, recovery
scripts/truths.py        .gwcu scope and persistence
scripts/observer.py      warm ScreenCast/PipeWire visual sensor
scripts/computer-use.sh  operator subcommands + local composition surface
runtimes/hermes/         slash-safe Hermes policy integration
install.sh               qualified install / upgrade path
uninstall.sh             safe removal entry point
```
