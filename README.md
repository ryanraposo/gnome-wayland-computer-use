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

**Accessibility when semantics exist. Pixels when they do not. Compositor precision when GNOME requires it. Machine verdicts instead of ritual deliberation.**

[Install](#install) · [Architecture](#architecture) · [Observation](#whole-screen-observation) · [Determinism](#deterministic-agent-experience) · [Diagnose](#diagnose)
</div>

---

`gnome-wayland-computer-use` is an agent operating layer for GNOME Wayland.
It preserves the human foreground whenever the platform exposes a safe route,
then escalates deliberately when the requested interaction cannot be delivered
otherwise.

The governing split is simple:

> **The agent decides intent. The operating layer decides mechanics.**

Version 2.3 has four planes:

| Plane | Surface | Job |
|---|---|---|
| **Observation** | XDG ScreenCast + PipeWire | truthful visible pixels |
| **Semantics** | AT-SPI / Cua AX | background-first structured control |
| **GNOME precision** | Cua + `winrects@cua` | authoritative Mutter geometry, verified activation, Cua compositor capture and agent cursor |
| **Recovery** | verified foreground → `/dev/uinput` + `ydotool` | explicit last-resort delivery |

The project-owned `desktop-capture@gnome-wayland-computer-use` extension is gone.
Screen observation requires no GNOME Shell extension. The full Hermes/Cua profile
uses **Cua's own WinRects GNOME adapter** for compositor knowledge; this repository
never vendors it and project observation never calls its D-Bus protocol.

## Architecture

```text
                              AGENT
                                │
                    intent / semantic choice
                                │
                         Cua target state
                      tree + target pixels
                                │
                 ┌──────────────┴──────────────┐
                 │                             │
                 ▼                             ▼
            SEMANTICS                    GNOME PRECISION
          AT-SPI / Cua AX                Cua + WinRects
                 │                             │
          semantic action              geometry / activation
                 │                     focus verification
                 └──────────────┬──────────────┘
                                │
                        structured verdict
                  confirmed / px / foreground /
                    unverifiable / refusal
                                │
               whole-screen discovery only if needed
                                │
                    XDG ScreenCast + PipeWire
```

Observation remains independent from Cua. Control remains independent from the
project's whole-screen capture implementation. That gives the system real
redundancy without duplicating Cua's control protocol.

The foreground rule is:

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

The public installer is a small determinism facade over the proven 2.3 migration
engine in `install-core.sh`. It verifies the current native foundation, applies
current Cua/Ubuntu policy, then lets the core perform the established migration,
skill installation, input recovery, and WinRects ownership work.

### Ubuntu 26.04 foundation

A normal Ubuntu 26.04 GNOME desktop is already PipeWire/WirePlumber based. The
installer **verifies first** and only repairs an incomplete host with official
Ubuntu packages required by the actual computer-use path:

- `pipewire`
- `wireplumber`
- `xdg-desktop-portal`
- `xdg-desktop-portal-gnome`
- `gstreamer1.0-pipewire`
- the required GStreamer base/good/tooling packages
- Python GI/GStreamer bindings when missing
- AT-SPI when missing
- `ydotool` only for the recovery plane

`pipewire-pulse` is an audio compatibility service, **not** a ScreenCast readiness
requirement. The project does not install it merely to make computer-use capture
work.

These distro packages are host foundation. Teardown never treats them as
project-owned packages.

### Hermes / Cua profile

When Hermes integration is selected, the installer:

1. locates `cua-driver`, installing it from Cua's official Driver installer when absent;
2. uses Cua's documented packaged helper only:
   `~/.cua-driver/packages/current/wayland-helper/install.sh`;
3. installs/updates `winrects@cua` from that Cua package;
4. records `cua-winrects-managed` only if this project caused WinRects to be installed;
5. reports whether GNOME precision is ready or requires one session reload.

If the installed Cua package does not contain the helper, precision degrades
cleanly. The project does **not** download, vendor, or recreate the extension.

### One session reload, explained

A full install may need one GNOME sign-out/sign-in for either or both reasons:

```text
SESSION RELOAD REQUIRED
├── new input-group membership
└── WinRects newly installed/updated and not loaded
```

Native ScreenCast observation and AT-SPI may already be ready before that reload.

## Deterministic agent experience

The common path is deliberately boring:

```text
known target
→ one Cua target/window state
→ AX when semantics ground the control
→ otherwise PX from the same target screenshot
→ consume the runtime's effect/escalation verdict
→ exact foreground only when required
→ verify only at a true decision boundary
```

A normal named-target task should require:

```text
0 update checks
0 broad diagnose calls
0 app/window enumeration when identity is already usable
0 whole-screen captures when target-level evidence is sufficient
0 blind retries of the same failed delivery rung
```

The agent should not re-derive whether a toolkit is GTK, Electron, browser-backed,
or pixel-only before acting. It tries the cheapest correct target-scoped route and
consumes the runtime's result.

### Machine verdicts

Project-owned helpers answer deterministic host questions with compact,
versioned JSON:

| Command | Contract | Purpose |
|---|---|---|
| `scripts/observe.sh --machine` | `gwcu.observe.v1` | whole-screen observation result |
| `scripts/observer.py client ...` | `gwcu.observer.v1` | persistent ScreenCast broker IPC |
| `scripts/app-identity.sh --resolve --machine NAME` | `gwcu.identity.v1` | resolved / ambiguous / missing launcher identity |
| `scripts/diagnose.sh --machine` | `gwcu.diagnose.v1` | one atomic four-plane diagnostic |
| `scripts/profile.sh read|refresh --machine` | `gwcu.profile.v1` | passive session capability state |

Coarse process exit classes remain small; JSON carries the precise `code`,
`retryable`, `terminal`, and deterministic `next` action. Scripts own fixed
fallback ladders. The model only decides when genuine semantic ambiguity remains.

## Whole-screen observation

The normal whole-screen entry point is:

```bash
OBSERVE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/observe.sh"

"$OBSERVE" --screen /tmp/screen.png
"$OBSERVE" --machine --screen /tmp/screen.png
"$OBSERVE" --media --screen
```

`--desktop` remains a compatibility alias for the visible display. Wallpaper is
configuration data; the project never hides application windows to manufacture
a special desktop layer.

### Lazy persistent ScreenCast broker

The observer socket is enabled in the user session, but **socket activation does
not request screen access**. The broker starts on the first capture request.

During an active task burst it keeps one:

```text
XDG ScreenCast session
→ portal-scoped PipeWire remote
→ GStreamer raw-frame pipeline
```

warm and returns the first fresh frame after each request. It closes the live
portal/PipeWire session after an idle timeout; the private socket remains ready
for later activation.

On ScreenCast v6 the broker prefers `pipewire-serial` through PipeWire
`target-object` when supported, retaining the numeric-node path for older
portal/plugin compatibility.

The broker is a speed layer, not a new authority or single point of failure.
`scripts/capture.sh` remains the independent direct path underneath it.

Technical broker failure can fall through to the direct capture ladder:

1. **XDG ScreenCast + PipeWire**;
2. **XDG Screenshot portal**;
3. **`gnome-screenshot`** on older compatible GNOME only;
4. **Shift+Print through `ydotool`** as final recovery.

A user-cancelled ScreenCast interaction is terminal for that request. The system
does not answer cancellation by opening another permission UI.

## Semantics and GNOME precision

AT-SPI remains the cheapest and least disruptive route when applications expose
roles/actions/values.

Cua's WinRects adapter belongs to **control**, not project observation. On GNOME
Cua may use it for authoritative window/frame geometry, GTK4 coordinate
reconstruction, exact Shell activation, focus verification before focus-bound
input, its own compositor capture path, and the compositor-owned agent cursor.

This repository provisions that adapter for the Cua-backed profile and diagnoses
its state. It does not duplicate the helper protocol.

## Pixel-only surfaces are real citizens

A GLFW/Vulkan/game/canvas/custom-rendered window can be plainly visible while
exposing little or no AT-SPI structure. Accessibility inventory is evidence of
semantic reachability, **not visual existence**.

Routing becomes:

```text
target known
    │
    ├─ semantics grounded
    │      → AX / background first
    │
    └─ semantics missing for the control
           │
           ├─ Cua has the GNOME target
           │      → use target pixels + compositor geometry
           │      → verified foreground only when required
           │
           └─ target cannot be bound
                  → whole-screen pixels
                  → bind the visible target
                  → return to target-scoped operation
```

A visible custom renderer is therefore **pixel-only**, not absent. An occluded
custom renderer with no trustworthy target route should escalate to foreground
discovery or refuse instead of guessing.

## Latency model

> **Route once → cheapest truthful evidence → deterministic action span → verify at the next decision boundary.**

The largest speed gains are deliberately architectural:

- no task-time update preflight;
- no broad diagnosis on success;
- no enumeration when the user already supplied the target;
- AX and PX reuse one Cua target state where the runtime provides both;
- whole-screen capture is discovery/explicit observation, not ritual;
- repeated screen frames reuse one warm ScreenCast/PipeWire session;
- actions piggyback verification when the runtime can prove the result.

Performance budgets in `DETERMINISM.md` are release targets until a nominated
GNOME 50 machine records real p50/p95 distributions. They are not represented as
measurements before that live evidence exists.

## Diagnose

Human diagnostics:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
```

Atomic agent diagnostic:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --machine
```

Passive failure-path profile:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/profile.sh read --machine
~/.agents/skills/gnome-wayland-computer-use/scripts/profile.sh refresh --machine
```

Do **not** run these before a healthy normal task. They exist to turn a capability
contradiction into information without an investigative agent loop.

Capabilities remain the four planes:

```text
Observation:       ready | degraded
Semantics:         ready | degraded
GNOME precision:   ready | reload_required | degraded | not_selected
Recovery:          ready | degraded
```

Diagnostics may verify that `org.cua.WinRects` is genuinely served by GNOME
Shell. Operational routing still goes through Cua rather than the project calling
WinRects methods itself.

## Ownership and teardown

Project state lives under:

```text
~/.local/state/gnome-wayland-computer-use/
    screencast-restore-token
    cua-winrects-managed       # migration ownership marker
    profile.json               # disposable capability state
    ownership.json             # durable project ownership
```

The restore token remains private and is never copied into `profile.json`.

Teardown may remove WinRects only when the authoritative managed marker says this
project caused its installation. A pre-existing Cua WinRects installation is
preserved. The obsolete project capture extension is always migration debris.
Observer user units/runtime files are project-owned and removable. Ubuntu desktop
foundation packages remain installed.

## Tests and release smoke

```bash
bash ./tests/skill-ux.sh
bash ./tests/latency-routing.sh
bash ./tests/determinism.sh
./tests/run.sh
```

The regression constitution protects both capability and behavior:

- direct ScreenCast remains independent of Cua/WinRects;
- persistent observer is lazy, private, v6-aware, and crash-fallback safe;
- portal cancellation remains terminal;
- restore tokens rotate;
- deterministic identity distinguishes resolved / ambiguous / missing;
- machine diagnostics emit one document;
- capability state is passive and secret-free;
- successful named-target routing performs no update/diagnose/list ritual;
- Cua's own helper installer remains the only WinRects source;
- agent-only setup never acquires Cua solely for WinRects;
- pre-existing WinRects ownership is preserved;
- pixel-only surface guidance remains first-class.

Required live Ubuntu 26.04 / GNOME 50 smoke before release includes:

- first ScreenCast consent;
- warm broker captures with recorded p50/p95 latency;
- restore-token rotation across restored sessions;
- broker idle/restart and crash fallback;
- AT-SPI semantic background action without foreground theft;
- WinRects ACTIVE after the required session reload;
- exact foreground escalation with a two-window input sentinel;
- pixel-only GLFW/Vulkan grounding;
- teardown preserving unrelated/pre-existing extensions and distro foundation.

Mutter Devkit remains a strong validation target for HiDPI/fractional-scaling and
virtual multi-monitor scenarios, not a 2.3 runtime dependency.

## Repository map

| Path | Purpose |
|---|---|
| `install.sh` | current Ubuntu/Cua policy + determinism installer facade |
| `install-core.sh` | proven 2.3 host provisioning / migration engine |
| `SKILL.md` | reflex-oriented Hermes computer-use contract |
| `runtimes/openai/SKILL.md` | portable/OpenAI runtime contract |
| `scripts/observe.sh` | normal whole-screen observation facade |
| `scripts/observer.py` | lazy persistent ScreenCast/PipeWire broker |
| `scripts/capture.sh` | independent direct ScreenCast recovery ladder |
| `scripts/app-identity.sh` | cached deterministic app/PWA identity resolver |
| `scripts/profile.sh` | passive capability state |
| `scripts/diagnose.sh` | capability-oriented human + machine diagnostics |
| `scripts/teardown.sh` | ownership-aware removal and restoration |
| `DETERMINISM.md` | machine contracts, latency constitution, design boundaries |
| `CAPABILITIES.md` | delivery-strength capability map |
| `PERF_NOTES.md` | latency and redundancy model |
| `tests/` | architecture, determinism, routing, and skill UX guards |
