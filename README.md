# gnome-wayland-computer-use

**An OS model for computer use on Ubuntu 26.04 GNOME Wayland.**

GWCU makes computer use behave like execution over a known machine instead of a conversation about screenshots.

The model supplies intent and handles genuine decisions. **WORLDLINE** maintains the current world model, preserves facts until evidence invalidates them, waits on declared outcomes, and interrupts reasoning only when reality diverges from the plan. **Cua Driver** remains the sole authority that actually controls the desktop. **`.gwcu`** carries durable truths across sessions.

> **Information over deliberation. Model calls at decision boundaries, local execution everywhere else.**
>
> **Cua controls. WORLDLINE knows. `.gwcu` remembers.**

- **Cua Driver controls the desktop.**
- **WORLDLINE maintains live, revisioned state and waits on postconditions.**
- **`.gwcu` remembers only durable repo/workspace truth.**
- **ScreenCast/PipeWire is an escalation sensor, not the default observation loop.**

```text
                   intent / contingent plan
                           │
                           ▼
                     ┌───────────┐
                     │ WORLDLINE │
                     │ revisions │
                     │ predicates│
                     └─────┬─────┘
          expected change  │  real conflict
              ┌────────────┘       └──────────→ model
              ▼
        Cua action span
              │
              ▼
     GNOME RemoteDesktop
          EIS / libei
              │
              ▼
           desktop
              │
       ┌──────┴───────────────┐
       ▼                      ▼
   AT-SPI events       ScreenCast / PipeWire
   direct oracles      only when visual truth
       └──────────┬───────────┘
                  ▼
           next WORLDLINE
              revision
```

The point is simple: **observation is an interrupt, not a ritual RPC.**

## Why WORLDLINE exists

Ordinary computer-use loops pay for every transition:

```text
observe → model → click → observe → model → type → observe → model → …
```

Most of those turns are bookkeeping. A click rarely invalidates everything the
agent already knew, and many outcomes have better evidence than pixels.

WORLDLINE treats desktop state like a revisioned system:

1. stamp a revision boundary;
2. consume accessibility and direct-oracle events;
3. invalidate only facts affected by those events/actions;
4. take visual evidence only when the transaction needs it;
5. evaluate postconditions and known branches locally;
6. continue deterministic execution;
7. interrupt the model only when reality violates the expected worldline.

A fact is **valid until invalidated**. A postcondition is an observation.

```text
action: click Save
    ↓
WORLDLINE sees document.dirty == false
    ↓
predicate satisfied
    ↓
continue

No screenshot.
No model turn.
```

WORLDLINE is not another agent and it is not another computer-use implementation. It is the machine-side continuity layer between decisions. The model does not need to know whether progress was established by AT-SPI, a process fact, a filesystem fact, a setting, or a visual escalation; it receives the next meaningful state when reasoning is actually required.

See [WORLDLINE.md](WORLDLINE.md) for the runtime and protocol.

## Control authority

Cua Driver is the only input/control authority.

Cua owns live semantic/pixel targeting, GNOME geometry, activation, pointer and
keyboard delivery, verification, effects and structured refusals. GWCU does not
fall back to `ydotool`, `/dev/uinput`, an RDP/VNC server or guessed focus.

On GNOME Wayland, Cua uses the compositor-approved Remote Desktop portal to
obtain its EIS/libei input session.

> [!TIP]
> GNOME calls this permission **Remote Desktop** or **remote control**. GWCU is
> not installing a remote-login service. It is authorizing local
> compositor-mediated pointer/keyboard control for Cua.

**No X11 or XWayland session is required.**

## The runtime in practice

### Known target

If the target is already grounded, start useful work immediately.

```text
known target
→ Cua state
→ one already-decided action span
→ WORLDLINE waits on postconditions
→ continue locally
→ model only on a real decision boundary
```

Example:

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

Two or more consecutive Cua actions that are fully determined by the same
evidence should cross the model/tool boundary once.

### Wait on reality, locally

WORLDLINE can capture a revision and evaluate predicates without asking the
model to re-observe:

```bash
"$ROOT/scripts/worldline-capture.sh" \
  --trigger action:save \
  --expect-json '[
    {"path":"settings.color_scheme","op":"eq","value":"prefer-dark"}
  ]'
```

Task-specific watchers can push direct evidence into the daemon:

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

Then a transaction can wait on `task.download.foo_zip == true` instead of
staring at a browser.

### Unknown app or PWA

One routing call resolves stable launcher/PWA identity:

```bash
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"
```

When managed truth is enabled, stable identity can be written to `.gwcu`, so
future runs skip rediscovery.

### Host contradiction

One recovery call owns the local diagnostic fan-out:

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

### Whole-screen visual evidence

Use it when the task is genuinely visual or semantic/direct evidence is
insufficient:

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
```

The observer is socket-activated and keeps the ScreenCast/PipeWire stream warm
for a short task burst. WORLDLINE can request that sensor for a revision; it
does not make screenshots the default control loop.

## `.gwcu`: durable truth

WORLDLINE state is transient. `.gwcu` is durable.

`.gwcu` stores low-churn repo/workspace facts such as stable app identity,
capability conclusions, calibration and user-authored preferences. It does not
store screenshots, task history, transient focus, documents, credentials or
WORLDLINE revision state.

Canonical schema:

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

For Git worktrees, managed mode writes `/.gwcu` to the root `.gitignore`
**before** creating `.gwcu`.

See [GWCU.md](GWCU.md).

## What WORLDLINE senses

The daemon is intentionally read-only.

Current built-in inputs include:

- AT-SPI accessibility events when the GI binding is available;
- session / desktop facts;
- GNOME settings;
- NetworkManager connectivity;
- requested `/proc` process facts;
- requested filesystem `stat` facts;
- task-specific event ingress;
- the existing ScreenCast/PipeWire observer when visual evidence is requested.

This is extensible by event source. Adding a watcher should add knowledge, not a
second control plane.

## Installation

The installer is qualified for Ubuntu 26.04 GNOME Wayland and deliberately pins
Cua Driver.

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

It:

- repairs the PipeWire, portal, AT-SPI and Python GI foundation;
- installs/qualifies the pinned Cua Driver and its GNOME helper;
- establishes one-time RemoteDesktop control consent;
- installs the skill and optional Hermes command plugin;
- asks whether managed `.gwcu` truth should be enabled;
- installs the WORLDLINE and visual-observer socket-activated user services;
- verifies Cua health before declaring the machine ready.

The first explicit whole-screen capture may still require ScreenCast consent.
Install does not open ScreenCast merely to preheat it.

Useful status surfaces:

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

Uninstall removes GWCU-managed skills/plugins, WORLDLINE and observer units,
runtime state, PATH edits and other integration-owned artifacts. Repo/workspace
`.gwcu` files remain local workspace content unless you remove them yourself.

Use `--remove-cua` to remove Cua only when GWCU provisioned it, or `--purge-cua`
for an explicit full Cua purge.

## Design rules

The short constitution is [DETERMINISM.md](DETERMINISM.md):

- Cua changes the desktop.
- WORLDLINE explains what changed and what remains valid.
- Direct truth beats visual inference.
- Predicates replace ritual re-observation.
- Determined mechanics stay inside one local call.
- `.gwcu` contains durable truth, never prompt prose.
- A real conflict returns control to the model.

Additional references:

- [WORLDLINE.md](WORLDLINE.md) — revision daemon and predicate protocol
- [GWCU.md](GWCU.md) — `.gwcu` durable truth contract
- [CAPABILITIES.md](CAPABILITIES.md) — runtime boundaries and surfaces
- [PERF_NOTES.md](PERF_NOTES.md) — where latency/call savings come from
