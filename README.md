<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
</pre>

# gnome-wayland-computer-use

**Cua-native computer use for Ubuntu GNOME Wayland.**

Cua owns control. This project makes the Ubuntu/GNOME substrate, whole-screen
observation, installation, and agent behavior deterministic.

[Install](#install) · [Architecture](#architecture) · [Observation](#whole-screen-observation) · [Agent behavior](#agent-behavior) · [Diagnose](#diagnose)
</div>

---

## Architecture

There are two authorities, with no overlap:

| Authority | Surface | Responsibility |
|---|---|---|
| **Cua Driver** | `computer_use` / MCP | semantics, target pixels, geometry, activation, input, cursor, effects, verification, refusals |
| **GWCU observation** | XDG ScreenCast + PipeWire | explicit whole-screen observation and discovery |

```text
                         AGENT
                           │
                        intent
                           │
              ┌────────────┴────────────┐
              │                         │
              ▼                         ▼
          CUA DRIVER                GWCU OBSERVER
    target state + actions       whole visible screen
              │                         │
       ┌──────┴──────┐           XDG ScreenCast
       ▼             ▼                  │
    AT-SPI       Cua WinRects        PipeWire
       │             │                  │
       └──────┬──────┘                  │
              ▼                         ▼
                    GNOME / MUTTER
```

Cua's GNOME helper is the compositor authority for window geometry, exact
activation, compositor capture, and the agent cursor. This repository neither
vendors nor calls its D-Bus protocol.

There is deliberately **no project-owned raw-input control plane**. No
`/dev/uinput` policy, `ydotool` daemon, input-group mutation, or parallel focus
logic is installed. If Cua refuses an unsafe delivery shape, that refusal is the
truth the agent consumes.

## Install

Run as the logged-in desktop user:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

Options:

```text
--hermes      require Hermes and install its computer-use skill integration
--agent-only  skip Hermes-specific files; Cua is still installed/required
--compat      stage files without requiring a live GNOME Wayland session
--unattended  automated invocation; privilege prompts may remain
```

### What the installer owns

The installer is one executable path. There is no runtime-patched secondary
installer.

It:

1. verifies GNOME Wayland;
2. verifies and repairs the Ubuntu-native observation/accessibility substrate;
3. installs or refreshes **Cua Driver from Cua's official installer** and requires its stable `health_report` surface;
4. installs/updates `winrects@cua` only through Cua's packaged helper;
5. installs the portable/Hermes skill payloads;
6. enables the private socket-activated whole-screen observer;
7. removes obsolete project-owned daemon/uinput artifacts from prior releases;
8. asks Cua for `health_report`, records `doctor --json` as diagnostic detail, and verifies project observation/Hermes integration;
9. exits successfully only when the result is ready, or explicitly reports the
   one GNOME reload still required for a newly installed/updated Shell helper.

### Ubuntu 26.04 foundation

Ubuntu 26.04 GNOME already provides most of this stack. The installer verifies
first and repairs only missing pieces with official Ubuntu packages:

- PipeWire + WirePlumber;
- XDG Desktop Portal + GNOME portal backend;
- GStreamer tools, PipeWire bridge, and PNG-capable plugins;
- Python GI plus GStreamer/GstVideo/GdkPixbuf introspection bindings;
- AT-SPI core.

`pipewire-pulse` is not a ScreenCast dependency and is not installed for this
project. `ydotool` is not part of the control architecture.

### Cua / GNOME precision

The only accepted GNOME helper source is the helper distributed with the
installed Cua package:

```text
~/.cua-driver/packages/current/wayland-helper/install.sh
```

A newly installed or updated helper can require one GNOME sign-out/in before the
Shell loads the new extension code. Cua and WinRects are upstream dependencies,
not project-owned artifacts; teardown preserves both.

## Agent behavior

The common path is intentionally small:

```text
known target
→ one Cua target/window state
→ AX if grounded, otherwise PX from that same state
→ consume Cua effect / verification / escalation
→ verified foreground only when Cua requires it
→ respect structured refusal
```

A normal task should perform:

```text
0 update checks
0 broad diagnostics
0 app/window enumeration when target identity is known
0 whole-screen captures when target-level evidence is enough
0 blind retries of the same failed Cua delivery shape
0 raw-input bypasses around Cua
```

Pixel-only Vulkan/GLFW/canvas/custom-rendered surfaces remain first-class. An
empty AX tree means "use the target pixels," not "search the whole desktop."

## Whole-screen observation

Explicit whole-screen observation is independent from Cua:

```bash
OBSERVE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/observe.sh"

"$OBSERVE" --screen /tmp/screen.png
"$OBSERVE" --machine --screen /tmp/screen.png
"$OBSERVE" --media --screen
```

The observer is socket activated. Starting the socket does not request capture
permission. On the first real observation, GNOME may ask the user to select a
monitor. During a task burst, one ScreenCast session, PipeWire remote, and raw
GStreamer stream stay warm for low-latency fresh frames.

A cancelled portal interaction is terminal for that request.

`scripts/capture.sh` remains a direct process fallback for broker/service
failures. It is observation infrastructure, never a second control backend.

## Deterministic helpers

| Command | Contract | Answer |
|---|---|---|
| `scripts/cua-health.py` | `gwcu.cua-health.v1` | thin transport for Cua's stable `health_report` structured result |
| `scripts/observe.sh --machine` | `gwcu.observe.v1` | whole-screen observation result |
| `scripts/observer.py client ...` | `gwcu.observer.v1` | warm broker IPC |
| `scripts/app-identity.sh --resolve --machine NAME` | `gwcu.identity.v1` | launcher identity |
| `scripts/diagnose.sh --machine` | `gwcu.diagnose.v2` | ready-now verdict for observation + Cua + GNOME helper state |
| `scripts/profile.sh read|refresh --machine` | `gwcu.profile.v2` | passive session snapshot |

Top-level `ok` means **the installed system is actually ready now**. Cua health is
not reconstructed by this project: `cua-health.py` opens a short-lived direct
stdio MCP session, asks Cua for `health_report`, and preserves its versioned
`structuredContent`. `cua-driver doctor --json` is carried separately for
installation/debug detail because warnings are diagnostic rather than a complete
readiness boolean.

## Diagnose

Human:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
```

Machine:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --machine
```

Possible top-level outcomes are deliberately small:

```text
ready
reload_required
wrong_session
observation_degraded
cua_degraded
```

## Teardown

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/teardown.sh
```

Teardown removes project-owned skills, observer units, routing, and cached state.
It preserves Cua Driver, Cua WinRects, distro packages, unrelated extensions,
and other upstream/user state.

## Release validation

The repository's validation workflow checks syntax, deterministic contracts,
observer privacy/lifecycle, identity resolution, Cua health transport, and
installer ownership boundaries. A release still needs one live Ubuntu 26.04
GNOME 50 smoke for the things CI cannot impersonate honestly:

- first ScreenCast consent + restore token;
- repeated warm captures;
- Cua `health_report` and doctor detail on the real session;
- Cua WinRects ACTIVE after any required GNOME reload;
- GTK semantic background action;
- pixel-only Vulkan/GLFW targeting;
- exact Cua foreground activation with a two-window sentinel.
