# WORLDLINE

WORLDLINE is GWCU's transient desktop-state and predicate runtime.

Its purpose is to remove the model from the mechanical
`observe → decide → act → observe` loop.

> **Observation is an interrupt, not an RPC.**

Cua Driver remains the sole control authority. WORLDLINE never injects input.
It watches, revises, invalidates, correlates and wakes deterministic work.

## Mental model

```text
model
  │ intent / contingent plan
  ▼
WORLDLINE ─────────────── conflict ─────────────→ model
  │
  │ expected action
  ▼
Cua Driver
  │
  ▼
desktop
  │
  ├─ AT-SPI events
  ├─ direct system/task facts
  └─ ScreenCast/PipeWire when requested
          │
          ▼
     WORLDLINE revision
          │
          ├─ predicate true → continue locally
          ├─ known branch   → continue locally
          └─ conflict       → model
```

The model defines intent and, when useful, the conditions under which a
transaction may continue. Cua performs desktop actions. WORLDLINE decides
whether reality still matches the transaction's assumptions.

## Valid until invalidated

A normal computer-use loop often treats every action as if it destroyed every
previous observation.

WORLDLINE does the opposite.

A fact remains valid until an event or declared effect invalidates its
dependency path.

```text
revision 41
  ui.focus = editor
  settings.color_scheme = default
  process.8214.alive = true

action changes theme

revision 42
  settings.color_scheme = prefer-dark     changed
  ui.theme_controls                       invalidated
  process.8214.alive = true               preserved
```

An unrelated notification should not make the agent rediscover the editor,
display, app identity and every other fact it already knows.

This is optimistic concurrency applied to UI state.

## A capture revision

One capture cycle is conceptually:

```text
capture(trigger):

  stamp revision boundary

  drain AT-SPI event batch

  update semantic cache
    changed sources
    ancestors
    relevant siblings
    focus
    window roots

  ingest direct-oracle events
    process
    filesystem
    D-Bus
    settings
    clipboard
    network
    task-specific watchers

  take visual evidence only when required

  correlate
    action
    semantic mutation
    visual mutation
    system mutation

  determine
    changed facts
    invalid facts
    preserved facts
    satisfied predicates
    conflicts

  if uncertain
    request the cheapest additional evidence

  seal revision

  wake transactions whose predicates became true
```

The current implementation provides this contract with a compact local daemon.
It deliberately leaves room for richer sensor adapters without changing the
revision/predicate protocol.

## Runtime state

WORLDLINE state lives under the user's runtime directory:

```text
$XDG_RUNTIME_DIR/gnome-wayland-computer-use/
  worldline.sock
  worldline/
    state.json
  observer.sock
```

This state is transient and session-scoped.

It is separate from `.gwcu`, which stores deliberately durable low-churn
repo/workspace truth.

## Event ingress

A watcher can contribute facts without teaching WORLDLINE about the watcher's
implementation.

```json
{
  "op": "event",
  "event": {
    "source": "task",
    "type": "download-complete",
    "facts": {
      "task.download.foo_zip": true
    },
    "invalidates": [
      "ui.downloads"
    ]
  }
}
```

Examples of useful direct evidence:

```text
filesystem watcher  → file exists / close_write
process watcher     → PID alive / exited
D-Bus               → application property changed
gsettings           → preference actually changed
network             → connectivity state
task watcher        → build/test/download completed
```

The rule is:

> Prefer the cheapest authoritative oracle over interpreting pixels.

## Predicates

WORLDLINE supports small deterministic predicates over fact paths.

Examples:

```json
{"path":"settings.color_scheme","op":"eq","value":"prefer-dark"}
{"path":"process.8214.alive","op":"eq","value":true}
{"path":"downloads.foo","op":"exists"}
{"path":"ui.dialog","op":"invalid"}
{"path":"task.build.status","op":"in","value":["passed","failed"]}
```

Supported operators in v1 are:

```text
exists
missing
changed
invalid
eq
ne
in
contains
```

A predicate is not a reasoning step. It is a local postcondition.

## Transactions

Clients can arm a transaction with predicates. When a later revision satisfies
them, WORLDLINE reports that transaction as woken.

The intended executor pattern is:

```text
model decides a deterministic span
        ↓
Cua executes already-decided actions
        ↓
WORLDLINE revisions arrive
        ↓
expected predicate becomes true
        ↓
executor continues without model re-entry
```

If the expected condition cannot be established, the caller can elect to treat
the miss as a conflict and return control to the model.

WORLDLINE does not decide arbitrary UI intent. It decides whether declared
conditions are true.

## AT-SPI

When `gir1.2-atspi-2.0` is available, the daemon registers a best-effort live
AT-SPI listener for focus, object and window events.

The adapter records compact semantic facts such as:

```text
source name
role
PID
ancestor chain
focus state
window/object mutation class
```

Those events invalidate affected semantic paths. The protocol does not depend
on GNOME Shell's restricted Introspect `GetWindows` API.

AT-SPI is a sensor, not an actuator.

## Visual sensor

The existing observer owns ScreenCast/PipeWire.

WORLDLINE requests a fresh observer frame only when a capture asks for visual
evidence. The current v1 records frame identity/dimensions and whether the frame
changed relative to the previous visual fact.

This deliberately keeps visual observation out of the default path.

Future visual adapters can add tile damage, ROI classification or local OCR
behind the same event/revision contract. They do not require a new model-facing
control loop.

## Built-in direct oracles

A capture can cheaply refresh:

- session type and desktop;
- Wayland display identity;
- login session active/locked state;
- GNOME color scheme;
- NetworkManager state/connectivity;
- requested process facts from `/proc`;
- requested filesystem facts through `stat`.

Task-specific watchers can push additional facts through event ingress.

These are evidence sources. None can inject pointer or keyboard input.

## CLI

Status:

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"

python3 "$ROOT/scripts/worldline.py" request --json '{"op":"status"}'
```

Capture:

```bash
"$ROOT/scripts/worldline-capture.sh" \
  --trigger action:click \
  --expect-json '[{"path":"ui.focus.name","op":"eq","value":"Search"}]'
```

Capture with visual evidence:

```bash
"$ROOT/scripts/worldline-capture.sh" \
  --trigger visual:needed \
  --visual
```

Invalidate a dependency explicitly:

```bash
"$ROOT/scripts/worldline-capture.sh" \
  --trigger action:navigate \
  --invalidate-json '["ui.window","ui.semantic"]'
```

Task event:

```bash
python3 "$ROOT/scripts/worldline.py" request --json '{
  "op":"event",
  "event":{
    "source":"task",
    "type":"tests-finished",
    "facts":{"task.tests.status":"passed"}
  }
}'
```

## Service lifecycle

The installer deploys:

```text
gnome-wayland-computer-use-worldline.socket
gnome-wayland-computer-use-worldline.service

gnome-wayland-computer-use-observer.socket
gnome-wayland-computer-use-observer.service
```

Both are private user services.

WORLDLINE is socket activated. The observer is independently socket activated
so no ScreenCast session is opened merely because WORLDLINE exists.

The uninstaller disables/removes both pairs and clears transient runtime state.

## Security and authority boundary

WORLDLINE must stay boring in one crucial way:

**it cannot control the computer.**

It may:

- receive events;
- read bounded local system state;
- ask the observer for visual evidence;
- maintain revision/fact state;
- evaluate predicates;
- wake deterministic transactions.

It may not:

- inject keyboard/pointer input;
- bypass a Cua refusal;
- invent a raw-input fallback;
- persist screenshots or task content as `.gwcu` truth;
- silently reinterpret uncertain state as success.

Cua owns actuation. The model owns unresolved intent. WORLDLINE owns the space
between them.
