# Capability Map

`gnome-wayland-computer-use` models GNOME Wayland as four complementary planes:
**Observation, Semantics, GNOME precision, Recovery.**

> Accessibility when semantics exist. Pixels when they do not. Compositor precision when GNOME requires it.

## Delivery-strength map

| Target | Evidence | Best delivery |
|---|---|---|
| Accessible control | AT-SPI | semantic background |
| Accessible control with bad GTK4 screen geometry | AT-SPI + Cua/WinRects geometry | semantic/background |
| Known GNOME window requiring focus-bound input | Cua + WinRects activation/focus verification | verified foreground |
| Visible custom renderer | ScreenCast pixels + Cua geometry when resolvable | pixels / verified foreground |
| Occluded custom renderer with no semantic route | insufficient safe target route | foreground discovery → structured refusal |
| Whole desktop | ScreenCast pixels | foreground pixels only |

Never fake delivery. Escalate when safe. Refuse when the compositor makes the
requested delivery shape impossible to verify.

## Observation

The project owns one independent visual surface: the **visible display**.

`--screen` selects it. `--desktop` is a compatibility alias.

### Hot path

XDG ScreenCast selects a monitor and exposes it through PipeWire. The helper
requests persistent permission where supported and rotates the returned restore
token after successful restoration.

Ubuntu 26.04 GNOME already treats PipeWire/WirePlumber as desktop foundation.
The installer verifies that foundation first and repairs missing official Ubuntu
portal/PipeWire/GStreamer packages only when necessary.

### Recovery

1. one-shot XDG Screenshot portal;
2. `gnome-screenshot` only where legacy GNOME still supports it;
3. Shift+Print through `ydotool`.

Portal denial ends the chain. A user saying “no” to ScreenCast is not permission
to open another capture UI.

### Independence

`capture.sh` does not call WinRects, Cua, or any project Shell service. That
means observation can remain usable when Cua is unavailable or WinRects is
waiting for a session reload.

## Semantics

AT-SPI is the preferred route when a target exposes roles, values, state, focus,
and actions. It enables background-first, low-round-trip workflows such as:

- inspect field → click → type complete text;
- semantic set/select/value actions;
- dialog discovery and deterministic form spans;
- structured read-back as verification.

Accessibility inventory is evidence of **semantic reachability**, not visual
existence.

## GNOME precision

The Hermes/Cua profile officially uses Cua's bundled `winrects@cua` GNOME Shell
adapter. Cua owns its code and D-Bus protocol; this project owns only provisioning
policy and installation-ownership metadata.

Cua WinRects can supply the runtime with:

- authoritative Mutter frame/buffer geometry;
- GTK4 screen-coordinate reconstruction from window-relative AT-SPI geometry;
- exact GNOME window activation;
- focus verification before focus-bound portal/libei input;
- compositor capture for Cua's own capture/window path;
- a compositor-owned agent cursor.

It is **not**:

- a `capture.sh` rung;
- a replacement for XDG ScreenCast;
- a fake desktop layer;
- a project-maintained fork;
- proof that arbitrary hidden-window raw pixel input is possible.

### Provisioning boundary

Only the Cua-backed profile invokes Cua's documented helper installer:

```text
~/.cua-driver/packages/current/wayland-helper/install.sh
```

`--agent-only` never installs Cua solely to obtain WinRects.

If the Cua package lacks that helper, GNOME precision degrades cleanly. No
independent extension download is attempted.

## Pixel-only applications

GLFW, Vulkan, games, canvas-heavy tools, remote-viewer surfaces, and other custom
renderers may expose no useful AT-SPI tree and may be absent from semantic window
inventory.

If the surface is visible:

1. capture the screen;
2. ground visually;
3. if Cua resolves the GNOME window, combine pixels with authoritative geometry;
4. use verified foreground activation only when necessary;
5. recapture after layout-changing actions.

If the surface is occluded and there is no trustworthy target identity, discover
it in the normal foreground or refuse. Do not guess raw input into an arbitrary
occluded Wayland surface.

## Foreground Preservation Contract

Preserve foreground by default. Change it only when the requested interaction
cannot be safely delivered otherwise. Verify the exact target before focus-bound
input.

Escalation:

1. semantic background;
2. target-addressed semantic/PX route;
3. exact activation + verified foreground;
4. `ydotool` recovery where appropriate;
5. structured refusal.

A `background_unavailable` or `background_occluded` result can be successful
safety behavior when it prevents input from leaking into the user's current
foreground.

## Recovery

`ydotool` + `/dev/uinput` remains a last-resort host recovery path. It is below
AT-SPI, Cua GNOME precision, and verified portal/libei foreground input.

The intended hierarchy is:

```text
AT-SPI / Cua semantic
        ↓
Cua GNOME adapter
        ↓
portal/libei verified foreground
        ↓
ydotool/uinput
```

## Session reload

A full Cua-backed installation may need one GNOME session reload for either or
both reasons:

- new `input` group membership;
- WinRects newly installed/updated and not active in the current Shell session.

The installer combines both into one final instruction. ScreenCast and AT-SPI
may already be usable before the reload.

## Ownership

The installer records:

```text
~/.local/state/gnome-wayland-computer-use/
    screencast-restore-token
    cua-winrects-managed
```

The WinRects marker exists only when this project caused the extension to be
installed. Teardown may then offer removal. Pre-existing WinRects is preserved.

The obsolete `desktop-capture@gnome-wayland-computer-use` extension is always
managed migration debris and should be removed if found.

## Completion proof

A task is complete when the requested postcondition is proven by the strongest
available evidence: structured semantic read-back, Cua target/focus verification,
or fresh pixels. A ceremonial screenshot is unnecessary when stronger proof
already exists.
