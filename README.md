<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
</pre>

# gnome-wayland-computer-use

**Deterministic, call-efficient computer use for Ubuntu 26.04 GNOME.**

Cua owns control. GWCU prepares the machine once, turns recurring desktop
mechanics into local programs, and turns durable observations into local
repo/workspace information in `.gwcu`.

The qualified session is GNOME Wayland. **No X11 or XWayland session is required.**

**Ubuntu 26.04 · GNOME 50 · Cua Driver 0.19.3 · RemoteDesktop/EIS/libei · AT-SPI · ScreenCast/PipeWire**
</div>

---

## Four hard advantages

| | Advantage | What changes |
|---|---|---|
| **01** | **Zero-ceremony known-target path** | A known app/window pays **0 GWCU setup calls** before Cua. |
| **02** | **Programs replace repeated deliberation** | `route` and `recover` compose several local probes inside **one outer call**. |
| **03** | **`.gwcu` turns observations into information** | A warm identity hit skips repeated launcher/PWA discovery. |
| **04** | **Installation finishes one-time work** | Dependencies, pinned Cua, control consent, Hermes integration, observer setup, and readiness proof happen up front. |

> **Remember invariants. Program the routine. Reason about the new.**

## What it feels like

A normal known-target task is intentionally boring:

```text
user intent
  ↓
[CUA] useful target/window state
  ↓
agent chooses AX or PX
  ↓
[CUA] useful action span
  ↓
verify only at a real decision boundary
```

GWCU adds **zero setup calls** there.

When uncertainty is reusable, the first encounter turns it into information:

```text
first time                         next time
──────────                         ─────────
[GWCU] route                       [GWCU] route
  .gwcu miss                         .gwcu hit
  local identity resolver            no identity scan
  exact identity                     no diagnostics
  write .gwcu                        no file churn
       ↓                                  ↓
[CUA] act                           [CUA] act
```

**Live Cua state always wins on contradiction.** Stored truth accelerates
mechanics; it never becomes control authority.

## Call budget

| Situation | GWCU setup calls before useful work |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen request | **1** — `observe.sh` |

A healthy known-target task has:

```text
0 task-time update checks
0 broad diagnostics
0 app/window enumeration
0 whole-screen prelude
0 toolkit classification
0 blind retries
0 raw-input bypasses
```

## Execution trees

Legend:

```text
[KNOW] information already available to the agent
[DECIDE] model decision
[TOOL] GWCU/local-program call
[CUA] Cua computer-use call
[BACK] compact result returned
[SAVED] work avoided
```

### Known target — zero GWCU setup calls

```text
[KNOW] target is already bound
   │
[DECIDE] request useful target state
   │
   └── [CUA #1]
         └── [BACK] target + AX/PX evidence
   │
[DECIDE] grounded semantic action is enough
   │
   └── [CUA #2]
         └── [BACK] effect/verification
   │
 done

[SAVED]
  no GWCU call
  no enumeration
  no screenshot prelude
  no diagnostics
  no toolkit/focus speculation
```

### Uncertain target, managed truths OFF

```text
[KNOW] name is known; exact launcher/PWA identity is uncertain
   │
[DECIDE] resolve only that uncertainty
   │
   └── [TOOL #1] profile.sh route --machine ChatGPT
         ├─ persistence disabled
         ├─ local identity resolver
         └── [BACK] gwcu.route.v1
              code=target_resolved
              identity_source=launcher
   │
[DECIDE] use returned identity
   │
   └── [CUA #1] useful state/action

[SAVED]
  diagnostics stay asleep
  no separate identity-script call
  no project-file parsing
  no whole-screen discovery

[NEXT TIME]
  identity resolver runs again because persistence is off
```

### Managed `.gwcu` ON — first encounter

```text
[KNOW] exact identity is uncertain
   │
[DECIDE] one route call
   │
   └── [TOOL #1] profile.sh route --machine ChatGPT
         ├─ resolve repo/workspace scope
         ├─ .gwcu miss
         ├─ local identity resolver
         ├─ exact identity found
         ├─ Git scope? ensure /.gwcu in root .gitignore first
         ├─ atomically write .gwcu
         └── [BACK] gwcu.route.v1
              code=target_resolved
              truths.code=recorded
   │
   └── [CUA #1] useful state/action

[SAVED]
  one outer call contains lookup + resolve + persistence
  no AGENTS.md mutation
  no model turn deciding what to remember
  machine/display state never enters project prose
```

### Managed `.gwcu` ON — warm encounter

```text
[KNOW] name is known; exact identity is absent from prompt/context
   │
[DECIDE] one route call
   │
   └── [TOOL #1] profile.sh route --machine ChatGPT
         ├─ nearest .gwcu found
         ├─ exact app identity hit
         ├─ no launcher/PWA resolver
         ├─ no rewrite
         └── [BACK] gwcu.route.v1
              evidence=[gwcu_truth]
              identity_source=gwcu
   │
   └── [CUA #1] useful state/action

[SAVED]
  100% of repeated launcher/PWA identity-resolution work
  all diagnostics
  all whole-screen discovery
  all AGENTS/project-prose parsing
  all unchanged write-back churn
```

### Host contradiction — one recovery call

```text
[KNOW] runtime result contradicts expected installed state
   │
[DECIDE] this is host uncertainty
   │
   └── [TOOL #1] profile.sh recover --machine
         ├─ cached profile read
         ├─ refresh only if stale/missing
         │    └─ diagnose.sh internally
         │         ├─ Cua health
         │         ├─ portal/session facts
         │         └─ observer facts
         └── [BACK] one deterministic next action

[SAVED]
  model does not perform
  read → interpret → refresh → interpret → diagnose → interpret
```

### Non-Git general workspace

`.gwcu` does not require Git:

```text
~/.gwcw/
├── .gwcu
├── scratch/
└── experiments/

work in ~/.gwcw/scratch
   ↓
[TOOL] route
   ├─ walk ancestors
   ├─ find ~/.gwcw/.gwcu
   ├─ reuse that scope
   └─ no .gitignore operation: this scope is not Git
```

The nearest-existing rule lets one general workspace carry durable local truths
for all of its descendants.

## `.gwcu`: the local truth file

`.gwcu` is a **file, not a directory**. Persistent machine/workspace truth lives
there, never in `AGENTS.md`.

It is canonical JSON:

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

| Section | Meaning | Regeneration policy |
|---|---|---|
| `observed` | low-churn facts directly observed about the environment | generated |
| `capabilities` | compact conclusions about what the scope/machine can do | generated |
| `calibration` | stable learned measurements/mappings | generated |
| `preferences` | user-authored behavior choices | preserved |
| `apps` | stable launcher/PWA identity | generated |

GWCU stores **conclusions, not observation transcripts**. `.gwcu` is not a task
log, conversation store, screenshot cache, clipboard cache, or raw diagnostic
dump.

Scope resolution:

```text
GWCU_SCOPE_ROOT override
→ nearest ancestor already containing .gwcu
→ Git worktree root
→ current working directory
```

For a managed Git scope, GWCU establishes this before writing truth:

```gitignore
# GWCU local machine/workspace truths
/.gwcu
```

If the ignore rule cannot be safely established, the persistent write fails.

See [`GWCU.md`](GWCU.md) for the full public contract.

Controls:

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/profile.sh" managed on --machine
"$ROOT/scripts/profile.sh" managed off --machine
"$ROOT/scripts/profile.sh" managed status --machine
"$ROOT/scripts/profile.sh" truths status --machine
"$ROOT/scripts/profile.sh" truths scope --machine
"$ROOT/scripts/profile.sh" truths regenerate --machine
```

Hermes:

```text
/computer-use managed on|off|status
/computer-use truths
```

`GWCU_TRUTHS=off` is the runtime override. `GWCU_PROJECT_MEMORY=off` remains an
accepted compatibility alias.

## Architecture

```text
                           AGENT
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
      CUA DRIVER         GWCU PROGRAMS       HERMES
      control/state      route/recover       orchestration
          │                  │
      AT-SPI / PX            ├─ .gwcu
      RemoteDesktop          └─ observer → ScreenCast/PipeWire
          │                  │
          └────────────── GNOME / MUTTER
```

Cua owns control, semantics, pixels, geometry, exact activation, input delivery,
verification, escalation, and refusal. GWCU owns Ubuntu/GNOME provisioning,
deterministic local programs, local truth, independent whole-screen observation,
and teardown.

No project-owned `/dev/uinput`, `ydotoold`, custom Cua daemon, RDP/VNC server,
parallel WinRects client, or model-invented focus stack belongs in the design.

## Install

Run as the logged-in desktop user:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

Require Hermes:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash -s -- --hermes
```

The installer:

1. qualifies Ubuntu 26.04 + GNOME 50;
2. repairs missing portal/PipeWire/AT-SPI/GStreamer foundation;
3. installs pinned **Cua Driver 0.19.3** through Cua's official installer;
4. installs Cua's packaged `winrects@cua` helper;
5. records the managed-`.gwcu` preference;
6. installs/enables Hermes integration when present;
7. establishes GNOME's one-time local control permission;
8. enables the warm whole-screen observer and proves installed-state health.

The `.gwcu` itself is created lazily in the real repo/workspace where durable
information is learned, or immediately when `managed on` is run inside a scope.

Native Ubuntu foundation:

```text
PipeWire + WirePlumber
XDG Desktop Portal + GNOME backend
RemoteDesktop + ScreenCast + Screenshot
EIS/libei + libxkbcommon
AT-SPI
Python D-Bus/GI + GStreamer/PipeWire bindings
```

`cua-driver doctor --json` is an install gate, followed by Cua's stable
`health_report`. `READY` means usable now.

## Why GNOME says “Remote Desktop”

> [!TIP]
> **This is GNOME's local compositor permission for agent input—not an RDP/VNC login service.**
>
> Cua requests `org.freedesktop.portal.RemoteDesktop`, receives an EIS/libei
> input session, and can persist GNOME's revocable restore token. GWCU installs
> no RDP/VNC server or raw-input daemon. The fresh-install handshake is one Cua
> pointer move: **no click, no key**.

ScreenCast is separate and appears only for explicit whole-screen observation.

## Hermes `/computer-use`

```text
/computer-use status
/computer-use managed on|off|status
/computer-use truths
/computer-use consent
/computer-use doctor
/computer-use help
```

## Semantic and pixel surfaces are equal citizens

```text
semantic evidence → Cua AX action
visual evidence   → Cua PX action
```

An AT-SPI-empty Vulkan, GLFW, canvas, game, video, or custom-rendered target is
**pixel-only, not absent**.

## Whole-screen observation

```bash
"$ROOT/scripts/observe.sh" --machine --screen /tmp/screen.png
```

The private socket-activated observer keeps one portal-scoped ScreenCast session
and PipeWire stream warm for a bounded task burst. `capture.sh` is a Screenshot
portal fallback only. Observation cannot inject input or call Cua.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Uninstall reverses installer-owned integration. Repo/workspace `.gwcu` files and
the ignore rules protecting them remain workspace content; uninstall does not
crawl arbitrary projects and destroy local truth/preferences.

## Release gate

CI proves call-budget, scope, `.gitignore`, cold/warm truth routing, recovery,
consent, installer, Cua, observer, and teardown contracts. Before merge, perform
one real Ubuntu 26.04 / GNOME 50 / Wayland smoke covering fresh install, actual
consent, semantic + pixel-only actions, warm observation, Hermes discovery,
`.gwcu` cold/warm routing, uninstall, and reinstall.

---

<div align="center">
<strong>Observe once. Turn it into information. Spend the next call on the task.</strong>
</div>
