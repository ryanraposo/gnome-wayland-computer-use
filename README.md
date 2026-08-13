<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
</pre>

# gnome-wayland-computer-use

**A deterministic computer-use runtime for Ubuntu 26.04 GNOME.**

Cua owns control. GWCU qualifies the machine, keeps observation warm, remembers
small project-local routing truths, and turns hard desktop sequences into local
programs before they can become model deliberation.

**Ubuntu 26.04 · GNOME 50 · Cua Driver 0.19.3 · RemoteDesktop/EIS/libei · AT-SPI · ScreenCast/PipeWire**

[Install](#install) · [Architecture](#architecture) · [Call budget](#call-budget) · [Programs compose mechanics](#programs-compose-mechanics) · [Project memory](#project-local-desktop-truths) · [Hermes](#hermes-native-orchestration) · [Observation](#whole-screen-observation) · [Uninstall](#uninstall)
</div>

---

## Why this exists

Ubuntu 26 has the native primitives for serious desktop agents. The useful
product is making them behave like **one prepared capability** instead of a Linux
puzzle the model solves again on every task.

> **The model decides intent. Programs collapse mechanics. Cua executes.**

- **Cua Driver** owns semantic + pixel control, target/window state, geometry,
  exact activation, input delivery, verification, escalation, and refusal.
- **GWCU** owns Ubuntu qualification, portal/PipeWire readiness, deterministic
  routing/recovery, project-local stable routing memory, whole-screen
  observation, installation, health composition, and teardown.
- **Hermes**, when present, supplies native clarification, one-turn programmatic
  fan-out, delegation, and managed background-process lifecycle.
- **The agent** spends calls on the user's actual task.

## Architecture

```text
                                  AGENT
                                    │
                                  intent
                                    │
                  ┌─────────────────┼─────────────────┐
                  │                 │                 │
                  ▼                 ▼                 ▼
             CUA DRIVER       GWCU PROGRAMS      HERMES RUNTIME
          target state/action  stable mechanics   orchestration
                  │                 │
       ┌──────────┴─────────┐       ├─ project AGENTS truths
       ▼                    ▼       ├─ route / recover
    AT-SPI          RemoteDesktop   └─ whole-screen observer
                          / EIS                 │
                          / libei           ScreenCast
       │                    │                   │
       └────────────┬───────┘                PipeWire
                    ▼                          │
                           GNOME / MUTTER ◀────┘
```

There is one control authority. GWCU does not install a shadow input stack: no
project uinput policy, no ydotool daemon, no custom Cua daemon, and no parallel
WinRects client.

Pixel-only Vulkan, GLFW, canvas, game, video, and custom-rendered surfaces are
first-class. An empty AT-SPI tree means **use target pixels**, not “search the
whole desktop.”

## Call budget

The north-star metric is **agent/tool boundaries**, not shell cleverness.

| Situation | GWCU setup calls before useful work |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen request | **1** — `observe.sh` |

A known target goes straight to one Cua target/window state. A normal task has:

```text
0 update checks
0 broad diagnostics
0 known-target enumeration
0 whole-screen prelude when target evidence is enough
0 toolkit-driven focus speculation
0 blind retries of the same failed delivery shape
0 raw-input bypasses
```

## Programs compose mechanics

A local subprocess is cheap. A model/tool boundary is expensive. Stable,
repeating mechanics therefore belong in tested scripts that can call other
scripts internally.

### Uncertain target: one route

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"
```

Inside that single outer call:

```text
project AGENTS truth lookup
→ launcher/PWA resolver only on miss
→ stable truth write-back only on confident resolution
→ gwcu.route.v1
```

The result stays small:

```text
target_resolved  → Cua target state with identity evidence
live_target      → no stable launcher truth; ask Cua for live target state
target_ambiguous → disambiguate only the returned candidates
```

Routing does not wake diagnostics merely because app identity is uncertain.

### Host contradiction: one recovery call

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

Inside that invocation:

```text
cached profile read
→ refresh only if stale/missing
  → diagnose.sh
    → Cua health + GNOME/observer facts
→ one deterministic next action
```

The model never needs to spend separate turns on `read → refresh → diagnose`.

## Project-local desktop truths

A confident route can piggyback a tiny managed block onto the current Git
worktree's root `AGENTS.md`:

```text
<!-- gwcu:desktop-truths:v1:start -->
## GWCU desktop truths
<!-- gwcu:app:v1 {"app_id":"…","desktop_id":"…","key":"…","name":"…"} -->
<!-- gwcu:desktop-truths:v1:end -->
```

This is **an invariant cache, not a task log**. It is bounded to 24 entries and
stores only low-churn identity facts: display name, desktop ID, app ID,
StartupWMClass, and app kind. There are no timestamps, screenshots, health
snapshots, user text, or window coordinates. Values are escaped so learned data
cannot break out of the managed comment record.

On the next route, an exact memory hit skips the launcher scan. Repeated hits do
not rewrite the file. User-authored `AGENTS.md` content outside the markers is
preserved byte-for-byte. `GWCU_PROJECT_MEMORY=off` disables write-back.

**Live Cua state always wins on contradiction.** Project memory is acceleration,
never authority.

## Hermes native orchestration

When Hermes exposes the corresponding tools, the skill routes work by kind:

```text
stable recurring mechanics → repository script
one-off mechanical fan-out → execute_code
independent reasoning       → delegate_task
bounded long process        → terminal background + notify_on_complete
real user choice            → clarify
interactive desktop action  → parent Cua loop
```

`clarify` is used for genuine user decisions, with the recommended choice first
and multi-select only when appropriate. `execute_code` collapses one-off
mechanical terminal/file/web fan-out into one model turn. `delegate_task` is for
independent reasoning or context-heavy work—not portal consent or interactive UI
steps. Bounded builds/tests can run with Hermes-managed background completion
instead of polling turns.

These are optional runtime accelerators, not required skill toolsets; the core
computer-use skill remains available with `computer_use` + terminal.

## Install

Run as the logged-in desktop user:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

Hermes integration:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash -s -- --hermes
```

The installer qualifies **Ubuntu 26.04 + GNOME 50 Wayland**, repairs only missing
host foundation, and elevates through `pkexec` first and `sudo` second when
needed. It verifies:

```text
PipeWire >= 0.3.40 + WirePlumber
RemoteDesktop + ScreenCast + Screenshot portals
EIS/libei + libxkbcommon
AT-SPI
Python D-Bus/GI + GStreamer/PipeWire bindings
```

It installs deliberately pinned **Cua Driver 0.19.3** through Cua's official
installer, installs Cua's packaged `winrects@cua` GNOME helper, installs the
portable/Hermes skill payloads, enables the private observer socket, and runs:

```bash
cua-driver doctor --json
```

as a hard installation gate before Cua's stable `health_report` readiness check.
`READY` means usable now; unresolved doctor/health failures abort with the
recovery information available.

The normal portal path creates no new GWCU udev rule. `video` membership is
considered only when Cua doctor specifically identifies a DRM/render-node
permission problem, and teardown owns the inverse when GWCU made that change.

## Portal consent

The system uses GNOME's native permission surfaces.

- **Control:** the first Cua foreground pointer/keyboard operation may show
  **Remote Desktop / remote control** consent. Cua uses the portal-issued
  EIS/libei input session.
- **Observation:** the first explicit whole-screen request may separately show
  **ScreenCast / screen selection** consent.

No X11 session is required. A denied/cancelled portal request ends that attempt;
the agent does not answer consent with a raw-input workaround.

## Whole-screen observation

```bash
OBSERVE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/observe.sh"
"$OBSERVE" --machine --screen /tmp/screen.png
"$OBSERVE" --media --screen
```

The private socket-activated observer keeps one portal-scoped ScreenCast session,
PipeWire remote, and GStreamer stream warm for a bounded task burst. Repeated
frames do not rebuild the capture chain. `capture.sh` is a direct XDG
Screenshot-portal fallback only; observation cannot inject input or call Cua.

## Diagnose

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --machine
```

Top-level `ok=true` means the installed system is actually ready. Cua's stable
`health_report` remains upstream control-health truth; GWCU composes it only with
the GNOME/observation facts it owns.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Uninstall reverses project-managed skills, observer units, managed Hermes
routing, PATH blocks, accessibility changes, exact legacy artifacts, project
state, and a GWCU-added `video` membership. It does **not** delete the managed
blocks GWCU wrote into user projects: those are project files, not installation
state.

Cua is removed only when GWCU provisioned it. `--keep-cua` always preserves it;
`--purge-cua` explicitly removes it. Ubuntu's portal/PipeWire/accessibility
packages remain host-owned.

## Release validation

CI guards shell/Python syntax, installer invariants, portal dependencies, Cua
qualification, ownership, observer lifecycle, skill UX, the 0/1/1/1 call budget,
managed AGENTS cold-write + warm-hit + opt-out behavior, comment-safe data
encoding, one-call recovery, Hermes-orchestration guidance, refusal handling,
and teardown reversibility.

Before merge, the remaining release gate is a clean graphical **Ubuntu 26.04 /
GNOME 50 / Wayland** smoke covering:

- fresh installer + elevation/package repair;
- successful pinned `cua-driver doctor` and Cua health;
- first RemoteDesktop consent + real click/type;
- first ScreenCast consent + repeated warm captures;
- active `winrects@cua` after any required Shell reload;
- Hermes `/reload-skills` + complete `computer_use` session;
- semantic, pixel-only, and exact-foreground actions;
- managed AGENTS first-write then memory-hit route;
- Hermes clarification/delegation/background behavior where applicable;
- uninstall + reinstall with no stale installation-owned state.

---

<div align="center">
<strong>Spend agent calls on the task.</strong>
</div>
