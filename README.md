<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
</pre>

# gnome-wayland-computer-use

**Native computer use for Ubuntu GNOME Wayland. No X11 escape hatch.**

Cua owns control. GWCU makes the Ubuntu/GNOME substrate, portal lifecycle,
whole-screen observation, installation, and agent behavior deterministic.

**Ubuntu 26.04 · GNOME 50 · Wayland · Cua Driver 0.19.3 · RemoteDesktop/libei · PipeWire**

[Install](#install) · [What gets installed](#what-gets-installed) · [Portal consent](#portal-consent) · [Agent path](#agent-path) · [Diagnose](#diagnose) · [Uninstall](#uninstall)
</div>

---

## The shape

```text
                              AGENT
                                │
                              intent
                                │
                  ┌─────────────┴─────────────┐
                  │                           │
                  ▼                           ▼
             CUA DRIVER                  GWCU OBSERVER
          target state + action          whole visible screen
                  │                           │
        ┌─────────┴──────────┐            ScreenCast
        ▼                    ▼                │
     AT-SPI          RemoteDesktop/libei   PipeWire
        │                    │                │
        └──────────┬─────────┘                │
                   ▼                          ▼
                         GNOME / MUTTER
```

**Cua Driver is the sole control authority.** It owns semantic and pixel actions,
window state, GNOME geometry, exact activation, input delivery, cursor behavior,
effects, verification, escalation, and structured refusals.

**GWCU owns integration and observation.** It qualifies Ubuntu 26.04, repairs the
portal/accessibility/media substrate, installs the agent operating layer, and
provides a fast independent whole-screen ScreenCast observer.

There is no project-owned `/dev/uinput` policy, ydotool daemon, custom Cua daemon,
parallel WinRects client, or requirement to log into X11/XWayland.

## Install

Run as the logged-in desktop user. The installer elevates only for Ubuntu package
repair or the rare group-membership recovery it can justify from Cua's doctor output.

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

For Hermes, make the integration mandatory:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash -s -- --hermes
```

Options:

```text
--hermes      require Hermes and install its computer-use integration
--agent-only  skip Hermes-specific files
--compat      stage files without mutating an unsupported/non-live host
--unattended  automate decisions; privilege and portal UI can still appear
```

### A deliberately pinned Cua

GWCU qualifies **Cua Driver 0.19.3** for this release and passes
`CUA_DRIVER_RS_VERSION=0.19.3` to Cua's official installer. It never asks for
"latest" during installation. That keeps a known GNOME/portal contract from
changing underneath users.

The standard 0.19.3 Linux release is built with Cua's `portal-input` feature—the
modern successor to the earlier `portal-libei` gate—so GNOME input uses the
RemoteDesktop portal + EIS/libei path without a GWCU fork or private binary.

A deliberate qualification override exists for maintainers:

```bash
GWCU_CUA_DRIVER_RS_VERSION=0.19.3 ./install.sh
```

Changing that value means **you are changing the qualified upstream runtime**;
it is not an update mechanism.

## What gets installed

On Ubuntu 26.04 the installer reads `/etc/os-release`, verifies the live GNOME
Wayland session, then repairs the explicit native foundation with apt when needed:

```text
ca-certificates curl
libglib2.0-bin
pipewire pipewire-bin wireplumber
xdg-desktop-portal xdg-desktop-portal-gnome
python3 python3-dbus python3-gi python3-gst-1.0
gstreamer1.0-tools gstreamer1.0-pipewire
gstreamer1.0-plugins-base gstreamer1.0-plugins-good
gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0
at-spi2-core
libei1 libxkbcommon0
```

It also verifies PipeWire is at least **0.3.40**, checks the GNOME `ScreenCast`,
`Screenshot`, and `RemoteDesktop` portal interfaces, and enables the project-owned
socket-activated observer with `systemctl --user enable --now`.

Then it installs the pinned Cua release through Cua's official installer, installs
Cua's packaged `winrects@cua` helper, installs the portable/Hermes skill payloads,
cleans exact obsolete GWCU units/udev artifacts from old releases, and runs
**`cua-driver doctor --json` as a hard installation gate**. A non-zero doctor exit
prints the health hints and aborts instead of leaving a cheerful half-install.

### DRM / `video` group

The portal path normally needs **no custom udev rule and no `video` group change**.
GWCU only offers/adds the logged-in user to `video` when Cua doctor itself fails
with a DRM/render-node permission symptom. In unattended mode that recovery is
automatic. Because supplementary group membership is established at login, the
installer then tells you to sign out/in and rerun instead of pretending the
current session changed underneath it.

## Portal consent

GNOME Wayland is the intended session. **Do not switch to X11.**

Two portal capabilities are intentionally distinct:

1. **Control:** the first Cua foreground pointer/keyboard operation may show
   GNOME's **Remote Desktop / remote control** consent. Approve it to allow the
   portal-issued EIS/libei input session.
2. **Observation:** the first explicit GWCU whole-screen observation may show a
   **ScreenCast / screen selection** consent. This observer is independent from Cua.

In the normal portal lifecycle these grants/tokens are reusable; GNOME may ask
again after a grant is revoked, portal state changes, or an upstream runtime
requires fresh consent. Cancelling a prompt is a real user decision and is never
worked around with raw input.

## Agent path

The normal task is aggressively small:

```text
known target
→ one Cua target/window state
→ AX when grounded / PX from the same state when visual
→ consume Cua effect + verification + escalation
→ verified foreground only when Cua requires it
→ respect structured refusal
```

A healthy normal task has:

```text
0 update checks
0 broad diagnostics
0 app/window enumeration when identity is known
0 whole-screen captures when target evidence is enough
0 blind retries of the same failed delivery shape
0 raw-input bypasses around Cua
```

AT-SPI-empty Vulkan, GLFW, canvas, game, video, and custom-rendered windows are
**pixel-only**, not absent. Cua remains responsible for targeting and safe delivery.

## Whole-screen observation

```bash
OBSERVE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/observe.sh"

"$OBSERVE" --screen /tmp/screen.png
"$OBSERVE" --machine --screen /tmp/screen.png
"$OBSERVE" --media --screen
```

The observer is private and socket-activated. Login itself does not request
capture permission. During a task burst it keeps one portal-scoped PipeWire
stream warm so fresh frames do not require rebuilding the entire capture chain.

`scripts/capture.sh` is the direct XDG Screenshot fallback when the broker cannot
serve a frame. It observes only; it never injects input or calls Cua.

## Diagnose

Human-readable:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
```

Machine-readable:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --machine
```

The installer also retains Cua's exact doctor output under:

```text
~/.local/state/gnome-wayland-computer-use/cua-doctor.json
~/.local/state/gnome-wayland-computer-use/cua-doctor.stderr
```

Top-level GWCU `ok=true` means **ready now**, not "probably configured." Cua's
stable `health_report` remains upstream truth; GWCU does not reconstruct it.

## Uninstall

Full uninstall:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

This reverses project-managed skill files, observer units, SOUL routing, managed
PATH edits, toolkit-accessibility changes, exact legacy artifacts, and a
GWCU-added `video` membership. It removes Cua **only when GWCU originally
provisioned it**. A Cua installation that already existed is preserved.

Explicit choices:

```bash
bash ./uninstall.sh --keep-cua   # always preserve Cua
bash ./uninstall.sh --purge-cua  # deliberately remove Cua even if it predated GWCU
```

Ubuntu apt packages and portal permission state are host-owned and deliberately
preserved; uninstalling a desktop integration should not casually dismantle the
desktop's media/accessibility substrate.

## Release validation

Repository CI covers shell syntax, installer invariants, the pinned Cua contract,
portal dependencies, teardown reversibility, deterministic routing, observer
privacy/lifecycle, identity resolution, and Cua health transport.

Before merge, the release still requires one real **Ubuntu 26.04 / GNOME 50 /
Wayland** smoke from a clean install:

- installer from scratch, including elevation;
- `cua-driver doctor` success on the installed pinned binary;
- first RemoteDesktop consent and a real Cua click/type;
- first ScreenCast consent and repeated warm capture;
- Cua WinRects ACTIVE after any required GNOME reload;
- Hermes `/reload-skills`, `computer_use`, semantic control, pixel-only control,
  and verified foreground activation;
- uninstall and reinstall without stale user units or PATH fragments.

That live graphical smoke is a release gate, not something CI claims to impersonate.

---

<div align="center">
<strong>The agent decides intent. Cua decides mechanics. GNOME stays Wayland.</strong>
</div>
