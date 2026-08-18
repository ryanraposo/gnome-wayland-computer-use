```text
                          ▄  ▄▄  ▄▄▄▄
                             ▄▀ 0x0 ▀▄
                              █  ───  █
                              █  ███  █
                               ▀▀   ▀▀
```

# gnome-wayland-computer-use

Agents have variable success using Linux. This project makes computer use dependable on the most popular Linux desktop out there, **Ubuntu 26.**

[Install](#install) · [Use it](#use-it) · [Why WORLDLINE exists](#why-worldline-exists) · [`.gwcu`](#gwcu) · [Invariants](#invariants)

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

GWCU has one control plane and three kinds of knowledge:

| Layer | Job |
|---|---|
| **Cua Driver** | The only desktop actuator. Semantic actions, pixels, pointer, keyboard, verification. |
| **WORLDLINE** | Transient revisioned state, invalidation, predicates, waits, branches and conflicts. |
| **`.gwcu`** | Durable repo/workspace truth worth reusing in another session. |

On GNOME Wayland, Cua uses `org.freedesktop.portal.RemoteDesktop` → EIS/libei for local compositor-approved input. GNOME may label that permission **Remote Desktop** or **remote control**. No RDP/VNC server, no raw-input daemon.

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

`/computer-use background` toggles background-control priority. OFF is the default because obvious foreground control is the fastest and most deterministic path.

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

The installer qualifies Ubuntu 26.04 GNOME Wayland, repairs Git, portal, PipeWire, AT-SPI and Python GI dependencies, installs or reuses pinned Cua Driver `0.19.3` and its GNOME helper, establishes persistent RemoteDesktop consent with a pointer-only bootstrap, installs the Agent Skill plus optional Hermes integration, configures `.gwcu` and background-control preferences, enables WORLDLINE and the lazy visual observer, removes provably old GWCU services and Hermes routing, and verifies Cua and WORLDLINE health before claiming success.

Run the installer as the logged-in desktop user, not by wrapping it in `sudo`.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

The public uninstaller uses current cleanup logic even when the installed bundle is older. Teardown removes only GWCU-owned integration and transient runtime state. Repo/workspace `.gwcu` content survives. Cua is preserved by default; `--remove-cua` removes only a GWCU-provisioned Cua installation, while `--purge-cua` is the explicit full purge.

## Invariants

- **Cua is the only actuator.** No `ydotool`, `/dev/uinput`, guessed focus, project RDP/VNC server or second control daemon.
- **WORLDLINE is read-only knowledge machinery.** Events and predicates do not gain input authority.
- **Facts are valid until invalidated.** Revisions preserve unrelated knowledge.
- **Postconditions replace ritual observation.** Model calls happen at decision boundaries.
- **`.gwcu` is durable only.** Runtime state stays transient.
- **Direct truth beats pixels.** Visual evidence is escalation, not ceremony.

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