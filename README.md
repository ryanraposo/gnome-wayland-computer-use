<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
</pre>

# gnome-wayland-computer-use

Fast, closed-loop computer use for Ubuntu GNOME Wayland.

**Accessibility when semantics exist. Pixels when they do not. Compositor precision when GNOME requires it.**

[Install](#install) · [Architecture](#architecture) · [Capture](#native-screen-capture) · [Diagnose](#diagnose)
</div>

---

`gnome-wayland-computer-use` is an agent operating layer for GNOME Wayland.
It preserves the human foreground whenever the platform exposes a safe route,
then escalates deliberately when the requested interaction cannot be delivered
otherwise.

Version 2.3 has four planes:

| Plane | Surface | Job |
|---|---|---|
| **Observation** | XDG ScreenCast + PipeWire | truthful visible pixels |
| **Semantics** | AT-SPI / runtime AX | background-first structured control |
| **GNOME precision** | Cua + `winrects@cua` | authoritative Mutter geometry, verified activation, Cua compositor capture and agent cursor |
| **Recovery** | portal/libei foreground input → `/dev/uinput` + `ydotool` | explicit last-resort delivery |

The project-owned `desktop-capture@gnome-wayland-computer-use` extension is gone.
Screen observation requires no GNOME Shell extension. The full Hermes/Cua profile
uses **Cua's own WinRects GNOME adapter** for compositor knowledge; this repository
never vendors it and `capture.sh` never calls its D-Bus protocol.

## Architecture

```text
                         AGENT
                           │
               gnome-wayland-computer-use
                    policy / routing
                           │
          ┌────────────────┴────────────────┐
          │                                 │
          ▼                                 ▼
     OBSERVATION                         CONTROL
 XDG ScreenCast                       Cua Driver
       │                                  │
   PipeWire                         ┌──────┴──────┐
       │                            │             │
 visible pixels                  AT-SPI       WinRects
                                    │             │
                              semantic AX     Mutter truth
                                                │
                                        geometry / activation
                                        Cua cursor / capture
                                        focus verification
```

The rule is:

> **Preserve foreground by default. Change it only when the requested interaction cannot be safely delivered otherwise. Verify the exact target before focus-bound input.**

Escalation:

1. semantic background;
2. target-addressed semantic or pixel route;
3. exact activation + verified foreground;
4. `ydotool` recovery where appropriate;
5. structured refusal when Wayland makes the requested delivery shape unsafe or impossible.

## Install

Run as the logged-in desktop user:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

```text
--hermes      require Hermes + Cua GNOME precision profile
--agent-only  install the shared stack without acquiring Hermes/Cua/WinRects
--compat      relax the GNOME/Wayland environment preflight
--unattended  mark automated execution
```

### Ubuntu 26.04 foundation

A normal Ubuntu 26.04 GNOME desktop already includes PipeWire/WirePlumber as
platform infrastructure. The installer **verifies first** and only repairs an
incomplete host with official Ubuntu packages such as `pipewire`,
`pipewire-pulse`, `wireplumber`, `xdg-desktop-portal`,
`xdg-desktop-portal-gnome`, `gstreamer1.0-pipewire`, and the required GStreamer
support. These are host foundation packages, not project-owned services.

### Hermes / Cua profile

When Hermes integration is selected, the installer:

1. installs/locates `cua-driver`;
2. uses Cua's documented packaged helper only:
   `~/.cua-driver/packages/current/wayland-helper/install.sh`;
3. installs/updates `winrects@cua` from that Cua package;
4. records `cua-winrects-managed` only if this project caused WinRects to be
   installed;
5. reports whether GNOME precision is ready or requires one session reload.

If the installed Cua package does not contain the helper, the precision
capability degrades cleanly. The project does **not** download a guessed copy of
the extension.

### One session reload, explained

A full install may need one GNOME sign-out/sign-in for either or both reasons:

```text
SESSION RELOAD REQUIRED
├── new input-group membership
└── WinRects newly installed/updated and not loaded
```

Native ScreenCast capture and AT-SPI can already be ready before that reload.

## Native screen capture

```bash
CAPTURE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/capture.sh"

"$CAPTURE" --screen /tmp/screen.png
"$CAPTURE" --timing --screen /tmp/screen.png
"$CAPTURE" --media --screen
```

`--desktop` remains a compatibility alias for the visible display. Wallpaper is
configuration data; the project never hides application windows to manufacture
a special desktop layer.

Capture order stays independent from Cua:

1. **XDG ScreenCast + PipeWire** — hot path, with persistent permission and
   rotating restore token where supported;
2. **XDG Screenshot portal** — one-shot recovery;
3. **`gnome-screenshot`** — older-GNOME compatibility only;
4. **Shift+Print through `ydotool`** — final hardware-level recovery.

If the user denies ScreenCast consent, denial is authoritative. The helper does
not surprise them with another permission UI. Writes are atomic.

## Semantics and GNOME precision

AT-SPI remains the cheapest and least disruptive route when applications expose
roles/actions/values.

Cua's WinRects adapter belongs to **control**, not capture routing. On GNOME it
can give Cua authoritative window/frame geometry, reconstruct screen coordinates
for GTK4 AT-SPI cases, activate an exact Shell window, verify focus before
focus-bound portal/libei input, capture from the compositor for Cua's own
window/capture path, and draw the compositor-owned agent cursor.

This repository provisions that adapter for the Cua-backed profile and diagnoses
its state. It does not duplicate the helper protocol or call it from
`scripts/capture.sh`.

## Pixel-only surfaces are real citizens

A GLFW/Vulkan/game/canvas/custom-rendered window can be plainly visible while
exposing little or no AT-SPI structure. Accessibility inventory is evidence of
semantic reachability, **not visual existence**.

Routing becomes:

```text
target known?
    │
    ├─ semantic target available
    │      → AX / background first
    │
    └─ semantic target unavailable
           │
           ├─ Cua can resolve a GNOME window
           │      → WinRects-backed geometry + pixels
           │      → verified foreground when necessary
           │
           └─ no trustworthy window target
                  → visible-screen pixels
                  → normal foreground discovery
                  → retry target binding
```

A visible custom renderer is therefore **pixel-only**, not absent. WinRects may
make its window precisely addressable even when its controls remain non-semantic.
An occluded custom renderer with no trustworthy target route should escalate to
foreground discovery or refuse rather than guess.

## Latency model

> **Route once → cheapest truthful evidence → deterministic action span → verify at the next decision boundary.**

ScreenCast remains independently useful even if Cua/WinRects is unavailable.
Conversely, Cua's own GNOME control/capture path can remain useful if this
project's ScreenCast path is degraded. That is real redundancy instead of a
chain of duplicated helpers.

## Diagnose

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --json
```

Diagnostics are capability-oriented:

```text
── Observation
✓ XDG ScreenCast
✓ PipeWire core
✓ WirePlumber
✓ GStreamer PipeWire bridge
✓ ScreenCast restore token state
✓ XDG Screenshot recovery

── Semantic control
✓ toolkit accessibility
✓ AT-SPI bus/socket

── Cua GNOME precision
✓ cua-driver
✓ Cua package wayland-helper
✓ Cua WinRects installed
✓ winrects@cua ACTIVE
✓ org.cua.WinRects served by GNOME Shell

── Input recovery
✓ /dev/uinput
✓ input group
✓ ydotoold

── Migration
✓ obsolete project capture extension removed

Observation:       READY
Semantic control:  READY
GNOME precision:   READY
Input recovery:    READY
```

Before the one required GNOME reload, precision reports `RELOAD REQUIRED`
instead of pretending the adapter is live.

## Ownership and teardown

State owned by this project lives under:

```text
~/.local/state/gnome-wayland-computer-use/
    screencast-restore-token
    cua-winrects-managed   # only when this installer caused installation
```

Teardown offers to remove WinRects only when that ownership marker exists. A
pre-existing Cua WinRects installation is preserved. The obsolete project
capture extension is always treated as migration debris and removed if found.

## Tests and release smoke

```bash
bash ./tests/skill-ux.sh
bash ./tests/latency-routing.sh
./tests/run.sh
```

The regression contract protects the boundary:

- `capture.sh` contains no WinRects call or project Shell service;
- ScreenCast remains the first capture rung;
- portal denial remains terminal;
- restore tokens rotate;
- Cua's own helper installer is used only for the Cua-backed profile;
- agent-only setup never acquires Cua solely for WinRects;
- installed/active/reload-required WinRects states are distinct;
- pre-existing WinRects ownership is preserved;
- pixel-only surface guidance remains first-class.

Required live GNOME 50 smoke before release includes cold/warm ScreenCast,
restore-token rotation, AT-SPI background action, WinRects ACTIVE after reload,
verified target activation, pixel-only GLFW/Vulkan grounding, GNOME 50 legacy
capture avoidance, and teardown preserving unrelated extensions.

Mutter Devkit is a strong future automation target for HiDPI/fractional-scaling
and virtual multi-monitor validation, but it is not a 2.3 runtime dependency.

## Repository map

| Path | Purpose |
|---|---|
| `install.sh` | host foundation, skill install, Cua profile provisioning |
| `SKILL.md` | Hermes-native computer-use contract |
| `runtimes/openai/SKILL.md` | portable/OpenAI-native contract |
| `scripts/capture.sh` | independent ScreenCast/PipeWire observation ladder |
| `scripts/diagnose.sh` | capability-oriented human + JSON diagnostics |
| `scripts/teardown.sh` | ownership-aware removal and restoration |
| `lib/checks.sh` | shared capability predicates |
| `CAPABILITIES.md` | delivery-strength capability map |
| `PERF_NOTES.md` | latency and redundancy model |
| `tests/` | architecture/routing/skill UX guards |
