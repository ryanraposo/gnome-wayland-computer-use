# gnome-wayland-computer-use

**Computer use for Ubuntu 26.04 GNOME Wayland that keeps already-known reality out of the model loop.**

GWCU sits around [Cua Driver](https://github.com/trycua/cua) and gives an agent a small OS model instead of a screenshot ritual.

> **Cua controls. WORLDLINE knows. `.gwcu` remembers.**

```text
model decides
→ Cua acts
→ WORLDLINE revises what changed
→ expected postcondition becomes true
→ continue locally
→ model re-enters only when reality creates a new decision
```

**Observation is an interrupt, not a ritual RPC.** Facts are valid until invalidated.

## What it is

GWCU has one control plane and three kinds of knowledge:

| Layer | Job |
|---|---|
| **Cua Driver** | The only desktop actuator. Semantic actions, pixels, pointer, keyboard, verification. |
| **WORLDLINE** | Transient revisioned state, invalidation, predicates, waits, branches and conflicts. |
| **`.gwcu`** | Durable repo/workspace truth worth reusing in another session. |
| **observer** | Optional ScreenCast/PipeWire visual evidence when direct truth is insufficient. |

On GNOME Wayland, Cua uses `org.freedesktop.portal.RemoteDesktop` → EIS/libei for local compositor-approved input. GNOME may label that permission **Remote Desktop** or **remote control**. GWCU installs no RDP/VNC server and no raw-input daemon.

**No X11 or XWayland session is required.**

## Use it

With Hermes, the installed skill owns the native slash command:

```text
/computer-use open YouTube and play something
/computer-use rename this file and put it in Downloads
/computer-use send the message I drafted
```

Everything after `/computer-use` is a normal task except these reserved operator subcommands:

```text
/computer-use status
/computer-use background [on|off|status]
/computer-use managed [on|off|status]
/computer-use truths
/computer-use consent
/computer-use doctor
/computer-use help
```

`/computer-use background` toggles background-control priority. OFF is the default because obvious foreground control is the fastest and most deterministic path. ON prefers background delivery where Cua actually supports it; Cua capability/runtime truth still has final say.

## Why WORLDLINE exists

Ordinary GUI automation repeatedly pays the model to rediscover expected outcomes:

```text
observe → model → click → observe → model → type → observe → model
```

GWCU preserves information until an event invalidates it:

```text
click Save
→ document.dirty == false
→ predicate satisfied
→ continue
```

WORLDLINE is transient. It can ingest authoritative facts from AT-SPI, filesystem/process state, D-Bus, settings, network/task watchers and, only when needed, visual evidence. A revision invalidates affected dependencies while unrelated facts survive.

WORLDLINE never injects input. A real conflict or undeclared branch returns control to the model.

## Determined work stays local

If two or more Cua actions are already determined by the same evidence, they cross the model/tool boundary once:

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

The runner keeps one Cua MCP session open. It splits only when fresh state changes the next decision, identity becomes stale, a branch is undeclared, Cua fails/refuses, or the user must choose.

Useful local surfaces:

```bash
# Wait for a postcondition / capture a WORLDLINE revision
"$ROOT/scripts/worldline-capture.sh" --trigger action:save \
  --expect-json '[{"path":"task.document.saved","op":"eq","value":true}]'

# Resolve an uncertain installed app / PWA once
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"

# Compose refresh + diagnosis after a host contradiction
"$ROOT/scripts/profile.sh" recover --machine

# Escalate to the visible screen only when needed
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
```

Direct truth beats visual inference. No fixed sleep or screenshot belongs between actions that are already decided.

## `.gwcu`

`.gwcu` stores low-churn local truth such as app identity, capability conclusions, calibration and user-authored preferences.

It never stores screenshots, documents, credentials, task history, transient focus/geometry, foreground-confidence guesses or WORLDLINE revisions.

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

The installer:

- qualifies Ubuntu 26.04 GNOME Wayland;
- repairs Git, portal, PipeWire, AT-SPI and Python GI dependencies;
- installs or reuses pinned Cua Driver `0.19.3`;
- installs Cua's GNOME helper;
- establishes persistent RemoteDesktop consent with a pointer-only bootstrap;
- installs the Agent Skill plus optional Hermes integration;
- configures `.gwcu` and background-control preferences;
- enables socket-activated WORLDLINE and the lazy visual observer;
- retires exact legacy GWCU `ydotoold` / uinput artifacts;
- verifies Cua and WORLDLINE health before claiming success.

The first whole-screen observation can still require separate ScreenCast consent.

Run the installer as the logged-in desktop user, not by wrapping it in `sudo`. It uses narrow privilege boundaries when needed.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Teardown removes only GWCU-owned integration and transient runtime state. Repo/workspace `.gwcu` content survives. Cua is preserved by default; `--remove-cua` removes only a GWCU-provisioned Cua installation, while `--purge-cua` is the explicit full purge.

## Invariants

- **Cua is the only actuator.** No `ydotool`, `/dev/uinput`, guessed focus, project RDP/VNC server or second control daemon.
- **WORLDLINE is read-only knowledge machinery.** Events and predicates do not gain input authority.
- **Facts are valid until invalidated.** Revisions preserve unrelated knowledge.
- **Postconditions replace ritual observation.** Model calls happen at decision boundaries.
- **`.gwcu` is durable only.** Runtime state stays transient.
- **Direct truth beats pixels.** Visual evidence is escalation, not ceremony.
- **Install and teardown mutate only state they can prove they own.**

## Project map

```text
SKILL.md                 runtime behavior contract
AGENTS.md                repository / installation instructions for agents
scripts/action-span.py   one-session Cua spans + control arbitration
scripts/worldline.py     revision store, predicates, waits, conflicts
scripts/profile.sh       app routing, truth composition, recovery
scripts/truths.py        .gwcu scope and persistence
scripts/observer.py      warm ScreenCast/PipeWire visual sensor
scripts/computer-use.sh  operator subcommands + internal composition surface
install.sh               qualified install / upgrade path
uninstall.sh             safe removal entry point
```

Human-facing project documentation lives here, in this README. Runtime contracts stay with the runtime (`SKILL.md`); repository instructions stay with the repository (`AGENTS.md`).
