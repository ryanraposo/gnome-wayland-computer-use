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

Cua owns control. GWCU prepares the machine once, compiles recurring desktop
mechanics into local programs, remembers only stable routing truths when allowed,
and keeps agent calls focused on the task.

The qualified session is GNOME Wayland; **no X11 session is required**.

**Ubuntu 26.04 · GNOME 50 · Cua Driver 0.19.3 · RemoteDesktop/EIS/libei · AT-SPI · ScreenCast/PipeWire**

[Install](#install) · [Four hard advantages](#four-hard-advantages) · [Call budget](#call-budget) · [Managed project truths](#managed-project-truths) · [Hermes commands](#hermes-computer-use) · [Consent](#why-gnome-says-remote-desktop) · [Uninstall](#uninstall)
</div>

---

## Four hard advantages

| | Advantage | What it changes |
|---|---|---|
| **01** | **Zero-ceremony known-target path** | A known app/window pays **0 GWCU setup calls** before Cua. No update check, broad diagnosis, enumeration, or whole-screen prelude. |
| **02** | **Programs replace repeated deliberation** | `profile.sh route` and `profile.sh recover` compose hard local sequences internally, so several probes still cost the model **one outer call**. |
| **03** | **The project can remember stable desktop truths** | With managed `AGENTS.md` blocks enabled, a warm identity hit skips launcher resolution and can remove **100% of the repeat identity-routing setup call**. |
| **04** | **Installation finishes the one-time work** | Ubuntu dependencies, pinned Cua, GNOME control consent, managed-memory preference, Hermes `/computer-use`, observer setup, health gates, and ownership bookkeeping are handled up front. |

> **Spend agent calls on the task.**

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

**Cua Driver is the sole control authority.** It owns semantic + pixel actions,
target/window state, GNOME geometry, exact activation, pointer/keyboard delivery,
verification, escalation, and structured refusal.

**GWCU is the Ubuntu operating layer.** It owns qualification, installation,
deterministic routing/recovery, project-local stable identity memory,
whole-screen observation, health composition, and teardown.

**Hermes is used for orchestration when orchestration is actually useful.**
Recurring mechanics stay in scripts; one-off deterministic fan-out can use
`execute_code`; independent reasoning can use `delegate_task`; bounded long work
can use managed background execution; real choices use `clarify`; interactive
desktop control stays in the parent Cua loop.

There is no project-owned `/dev/uinput` policy, `ydotoold`, custom Cua daemon,
parallel WinRects client, or model-invented focus stack.

## Call budget

| Situation | GWCU setup calls before useful work |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen request | **1** — `observe.sh` |

Known target:

```text
one Cua target/window state
→ AX when grounded / PX from the same state when visual
→ useful action span
→ verify only when the next decision depends on new state
```

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

## Programs compose programs

A local subprocess is cheap. An agent/tool boundary is expensive.

### Uncertain target: one call

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"
```

Inside that invocation:

```text
managed project truth lookup
→ deterministic launcher/PWA resolver only on miss
→ stable truth write-back only when enabled + confidently resolved
→ one gwcu.route.v1 result
```

Possible results stay small:

```text
target_resolved  → Cua target state with identity evidence
live_target      → no stable launcher truth; ask Cua for live target state
target_ambiguous → disambiguate only returned candidates
```

Routing does not wake diagnostics merely because identity is uncertain.

### Host contradiction: one call

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

Inside:

```text
cached profile read
→ refresh only if stale/missing
  → diagnose.sh
    → Cua health + GNOME/observer facts
→ one deterministic next action
```

The model never pays separate turns for
`read → interpret → refresh → interpret → diagnose → interpret`.

## Managed project truths

Managed memory is intentionally tiny. When enabled, `profile.sh route` may
maintain one bounded block in the current Git worktree's root `AGENTS.md`:

```text
<!-- gwcu:desktop-truths:v1:start -->
## GWCU desktop truths
<!-- gwcu:app:v1 {"app_id":"…","desktop_id":"…","key":"…","name":"…"} -->
<!-- gwcu:desktop-truths:v1:end -->
```

Eligible fields are deliberately boring:

- display name;
- desktop ID;
- app ID;
- `StartupWMClass`;
- app kind.

It never stores screenshots, user text, timestamps, health snapshots, task
history, window coordinates, geometry, or transient focus state. The block is
bounded to 24 entries, deterministic, one-record-per-line, regex-addressable,
comment-safe, and preserves user-authored `AGENTS.md` content outside the
markers.

A warm hit skips launcher resolution entirely. That can remove **100% of the
repeat identity-routing setup call**.

**Live Cua state always wins on contradiction.** The block is an acceleration
cache, never authority.

The installer asks once:

```text
Would you like to allow managed AGENTS.md blocks? They can reduce turns/calls by up to 100% for repeat identity-routing setup [Y/n]:
```

Change it later:

```bash
/computer-use managed
/computer-use managed on
/computer-use managed off
/computer-use managed status
```

or, without Hermes:

```bash
"$ROOT/scripts/profile.sh" managed on --machine
"$ROOT/scripts/profile.sh" managed off --machine
"$ROOT/scripts/profile.sh" managed status --machine
```

`GWCU_PROJECT_MEMORY=off` remains the runtime override.

## Install

Run as the logged-in desktop user. The installer elevates only for host mutation
that actually needs root.

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

Require Hermes integration:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash -s -- --hermes
```

The canonical pipe install still presents the managed-AGENTS choice through
`/dev/tty`. `--unattended` accepts the default and suppresses that text prompt;
GNOME permission UI may still appear because compositor consent cannot be
silently granted.

The installer:

1. qualifies Ubuntu 26.04 + GNOME 50;
2. repairs only missing portal/PipeWire/AT-SPI/GStreamer foundation;
3. installs deliberately pinned **Cua Driver 0.19.3** through Cua's official installer;
4. installs Cua's packaged `winrects@cua` helper;
5. records the managed-AGENTS preference;
6. installs + enables the native Hermes `/computer-use` plugin when Hermes is present;
7. establishes GNOME's one-time local control permission;
8. enables the private warm whole-screen observer and proves Cua/host health.

The native Ubuntu foundation is explicit:

```text
PipeWire + WirePlumber
XDG Desktop Portal + GNOME portal backend
RemoteDesktop + ScreenCast + Screenshot interfaces
EIS/libei + libxkbcommon
AT-SPI
Python D-Bus/GI + GStreamer/PipeWire bindings
```

`cua-driver doctor --json` is a hard install gate, followed by Cua's stable
`health_report`. `READY` means the system is usable now.

## Why GNOME says “Remote Desktop”

> [!TIP]
> **This is GNOME's local compositor permission for agent input—not an RDP/VNC login service.**
>
> Cua requests `org.freedesktop.portal.RemoteDesktop` because GNOME exposes
> compositor-approved pointer + keyboard delivery through that portal. GNOME
> then gives Cua an **EIS/libei** input session. GWCU does not install an RDP/VNC
> server, a raw-input daemon, a project input udev rule, or a second control
> backend.
>
> During a fresh install, GWCU explains what is about to happen and counts down
> **3 → 2 → 1** before the GNOME prompt. The bootstrap uses Cua's public
> `move_cursor` operation only to establish the session: **one pointer move, no
> click, no key**. Cua can then persist GNOME's revocable restore token at
> `~/.config/cua-driver/libei-persistent.token`, so the normal case does not ask
> again.
>
> Verify the contract any time with **`/computer-use consent`** or:
>
> ```bash
> ~/.agents/skills/gnome-wayland-computer-use/scripts/portal-control.py --status
> ```
>
> The status reports the RemoteDesktop portal, EIS/libei transport, restore-token
> path, and the absence of GWCU's retired raw-input/control-daemon machinery.

ScreenCast is separate. The first explicit whole-screen observation may ask which
display to share.

## Hermes `/computer-use`

When Hermes is detected, the installer places a user plugin under
`~/.hermes/plugins/gnome-wayland-computer-use/` and enables it through Hermes's
own plugin configuration.

The plugin registers `/computer-use` through Hermes's native command API, so it
appears in command discovery/autocomplete with a description and argument hint:

```text
/computer-use status
/computer-use managed
/computer-use managed on|off|status
/computer-use consent
/computer-use doctor
/computer-use help
```

The command backend is itself deterministic:

```bash
~/.hermes/skills/computer-use/scripts/computer-use.sh
```

`managed` changes the persistent project-memory preference. `consent` shows the
RemoteDesktop/EIS verification surface. `doctor` runs deterministic host
diagnosis. `status` composes the useful high-level facts without forcing the
agent to rediscover them.

## Semantic and pixel surfaces are equal citizens

A browser button and a Vulkan viewport are different surfaces, not different
classes of legitimacy.

```text
semantic evidence → Cua AX action
visual evidence   → Cua PX action
```

An AT-SPI-empty Vulkan, GLFW, canvas, game, video, or custom-rendered target is
**pixel-only, not absent**. The agent stays attached to the real target rather
than escalating into whole-desktop discovery because semantic structure is
sparse.

## Whole-screen observation

```bash
OBSERVE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/observe.sh"
"$OBSERVE" --machine --screen /tmp/screen.png
"$OBSERVE" --media --screen
```

The private socket-activated observer keeps one portal-scoped ScreenCast session,
PipeWire remote, and GStreamer stream warm for a bounded task burst. Repeated
frames do not rebuild the capture chain.

`scripts/capture.sh` is an XDG Screenshot-portal-only fallback. Observation
cannot inject input or call Cua.

## Diagnose

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --machine
```

Top-level `ok=true` means the installed system is actually ready. Cua's stable
`health_report` remains upstream control-health truth; GWCU composes it only with
the Ubuntu/GNOME facts it owns.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Uninstall reverses project-managed skills, the Hermes command plugin, observer
units, managed Hermes routing, PATH blocks, accessibility changes, exact legacy
artifacts, project state, and a GWCU-added `video` membership.

Cua is removed only when GWCU provisioned it. `--keep-cua` always preserves it;
`--purge-cua` explicitly removes it. Ubuntu's portal/PipeWire/accessibility
packages and GNOME permission state remain host-owned.

Managed blocks previously written into user repositories remain repository
content; uninstall does not silently edit arbitrary project files.

## Release validation

CI guards:

- the **0 / 1 / 1 / 1** call budget;
- one-call route/recovery composition;
- managed-memory cold write, warm hit, opt-out, bounded/comment-safe records;
- persistent managed preference;
- pointer-only RemoteDesktop bootstrap;
- native Hermes `/computer-use` plugin registration;
- Ubuntu package + portal qualification;
- Cua pin and health contracts;
- observer lifecycle and consent boundaries;
- absence of shadow raw-input machinery;
- reversible installer-owned state.

Before merge, the remaining release gate is a clean graphical **Ubuntu 26.04 /
GNOME 50 / Wayland** smoke covering fresh install, actual GNOME consent,
semantic + pixel-only Cua actions, warm observation, Hermes command discovery,
managed-AGENTS warm routing, uninstall, and reinstall.

---

<div align="center">
<strong>Remember invariants. Program the routine. Reason about the new.</strong>
</div>
