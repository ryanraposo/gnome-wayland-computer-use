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

Cua owns control. GWCU qualifies the machine, keeps observation fast, and turns
recurring desktop uncertainty into compact local answers before it can become
agent deliberation.

**Ubuntu 26.04 · GNOME 50 · Cua Driver 0.19.3 · RemoteDesktop/EIS/libei · AT-SPI · ScreenCast/PipeWire**

[Install](#install) · [Architecture](#architecture) · [Call budget](#call-budget) · [Scripts compose scripts](#scripts-compose-scripts) · [Observation](#whole-screen-observation) · [Diagnose](#diagnose) · [Uninstall](#uninstall)
</div>

---

## Why this exists

Ubuntu 26 has the right native primitives for serious desktop agents. The
problem is making them behave like **one capability** instead of a Linux puzzle
the model solves again on every task.

GWCU moves that work out of the agent loop:

- **Cua Driver** owns semantic + pixel control, target state, geometry, exact
  activation, input delivery, verification, escalation, and refusal.
- **GWCU** owns Ubuntu qualification, portal/PipeWire readiness, deterministic
  routing context, whole-screen observation, installation, health composition,
  and teardown.
- **The agent** chooses intent and spends calls on the task.

> **The model decides intent. Scripts collapse uncertainty. Cua executes.**

## Architecture

```text
                                  AGENT
                                    │
                                  intent
                                    │
                      ┌─────────────┴─────────────┐
                      │                           │
                      ▼                           ▼
                 CUA DRIVER                  GWCU OBSERVER
              target state + action          whole-screen evidence
                      │                           │
          ┌───────────┴────────────┐          ScreenCast
          ▼                        ▼              │
       AT-SPI              RemoteDesktop/EIS   PipeWire
                                  / libei          │
          │                        │               │
          └────────────┬───────────┘               │
                       ▼                           ▼
                              GNOME / MUTTER
```

There is one control authority. GWCU does not install a second raw-input stack:
no project uinput policy, no ydotool daemon, no custom Cua daemon, and no parallel
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

For a known target, the hot path is simply:

```text
one Cua target/window state
→ AX when grounded / PX from that same state when visual
→ useful action span
→ verification only when the next decision depends on it
```

A normal task has:

```text
0 update checks
0 broad diagnostics
0 known-target enumeration
0 whole-screen prelude when target evidence is enough
0 blind retries of the same failed delivery shape
0 raw-input bypasses
```

## Scripts compose scripts

A local subprocess is cheap. A model/tool round-trip is expensive.

GWCU therefore exposes **composed agent-facing commands** instead of making the
agent fan out through low-level probes.

### Unknown target: one routing call

```bash
ROOT="$HOME/.agents/skills/gnome-wayland-computer-use"
"$ROOT/scripts/profile.sh" route --machine "ChatGPT"
```

`gwcu.route.v1` combines cached session context with deterministic launcher/PWA
identity and returns one next step:

```text
target_resolved  → Cua target state with identity evidence
live_target      → launcher metadata absent; ask Cua for live target state
target_ambiguous → disambiguate only the returned candidates
```

Routing does **not** run diagnostics merely because identity is uncertain.

### Host contradiction: one recovery call

```bash
"$ROOT/scripts/profile.sh" recover --machine
```

Inside that one invocation:

```text
cached profile read
→ refresh only if stale/missing
  → diagnose.sh
    → Cua health + GNOME/observer facts
→ one structured next action
```

The model never needs to spend three turns on `read → refresh → diagnose`.

Lower-level helpers remain available for testing and maintenance; the skill tells
agents to prefer the composed route/recovery surfaces.

## Install

Run as the logged-in desktop user:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

Hermes integration:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash -s -- --hermes
```

The installer is qualified for **Ubuntu 26.04 + GNOME 50 Wayland** and elevates
through `pkexec` or `sudo` only when host repair requires it.

It verifies/repairs the explicit Ubuntu substrate:

```text
PipeWire + WirePlumber
XDG Desktop Portal + GNOME portal backend
RemoteDesktop + ScreenCast + Screenshot interfaces
EIS/libei + libxkbcommon
AT-SPI
Python D-Bus/GI + GStreamer/PipeWire bindings
```

Then it installs the deliberately pinned **Cua Driver 0.19.3** through Cua's
official installer, installs Cua's packaged `winrects@cua` helper, enables the
private observer socket, and runs:

```bash
cua-driver doctor --json
```

as a hard readiness gate. `READY` means usable now; a failing doctor means the
installer fails with the recovery information it actually has.

The normal portal path creates no new GWCU udev rule. `video` group membership is
considered only when Cua doctor specifically reports a DRM/render-node permission
problem, and teardown owns the inverse when GWCU made that change.

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
frames do not rebuild the entire capture chain.

`scripts/capture.sh` is a direct XDG Screenshot-portal fallback. Observation
cannot inject input or call Cua.

## Diagnose

Human-readable:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
```

Machine-readable:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --machine
```

Top-level `ok=true` means the installed system is actually ready. Cua's stable
`health_report` remains upstream control-health truth; GWCU composes it only with
the GNOME/observation facts it owns.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Uninstall reverses project-managed skills, observer units, managed Hermes routing,
PATH blocks, accessibility changes, exact legacy artifacts, project state, and a
GWCU-added `video` membership.

Cua is removed only when GWCU provisioned it. `--keep-cua` always preserves it;
`--purge-cua` explicitly removes it. Ubuntu's portal/PipeWire/accessibility
packages remain host-owned.

## Release validation

CI guards the installer contract, portal dependencies, Cua pin, ownership model,
observer lifecycle, skill UX, one-call routing/recovery, deterministic refusal
handling, teardown reversibility, and regression suite.

Before merge, the remaining release gate is a clean graphical **Ubuntu 26.04 /
GNOME 50 / Wayland** smoke covering:

- fresh installer + elevation/package repair;
- successful pinned `cua-driver doctor`;
- first RemoteDesktop consent + real click/type;
- first ScreenCast consent + repeated warm captures;
- active `winrects@cua` after any required Shell reload;
- Hermes `/reload-skills` + complete `computer_use` session;
- semantic, pixel-only, and exact-foreground actions;
- uninstall + reinstall with no stale project state.

---

<div align="center">
<strong>Spend agent calls on the task.</strong>
</div>
