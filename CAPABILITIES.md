# Capability Map

`gnome-wayland-computer-use` treats GNOME Wayland as several complementary
surfaces instead of pretending one API can represent the whole desktop.

## Capability ladder

| Capability | Primary | Degrades to |
|---|---|---|
| Semantic inspection | AT-SPI / runtime AX | visible pixels |
| Semantic click/value/text | runtime driver | coordinate delivery → foreground |
| Visible-screen capture | XDG ScreenCast + PipeWire | Screenshot portal → legacy GNOME → Shift+Print |
| Pixel-only GLFW/Vulkan/canvas | screen pixels + coordinates | normal foreground/window selection |
| Installed web-app identity | live app/window identity | desktop launcher cache → browser identity |
| Synthetic keyboard/pointer recovery | runtime driver | `/dev/uinput` + `ydotool` |
| Privileged Ubuntu mutation | graphical `pkexec` | explicit manual action |

## Screen capture

The capture helper intentionally owns one truthful visual surface: the **visible
display**.

`--screen` selects it directly. `--desktop` remains a compatibility alias.
There is no hidden-window desktop compositor, WinRects verification transaction,
or project-owned Shell extension.

### Hot path

XDG ScreenCast selects one monitor and exposes it through PipeWire. On portal
v4+, the helper requests persistent permission and stores the returned restore
token. Restore tokens are single-use, so every successful restored session
replaces the cached token with the new token returned by the portal.

That turns the permission chooser into a first-use/revocation boundary rather
than a tax on every screenshot.

### Recovery

1. one-shot XDG Screenshot portal;
2. `gnome-screenshot` only where the legacy GNOME path is still viable;
3. Shift+Print through `ydotool`.

Portal cancellation stops the chain rather than opening another permission UI.
All writes are atomic.

## Wallpaper and desktop icons

A wallpaper asset is configuration, not a special screenshot surface. Resolve
GNOME's configured background file when the user wants the image itself.

Desktop icons supplied by another extension are ordinary visible pixels. This
skill does not depend on that extension's scene graph or private geometry.

## Accessible applications

AT-SPI is the cheapest reliable observation surface when the target exposes
roles, names, values, focus, and actions. It supports low-round-trip workflows
such as:

- inspect field → click → type complete text;
- set accessible menu/select/slider values semantically;
- discover dialog roles and fill deterministic fields;
- inspect text-heavy applications without pixels;
- verify state through structured driver read-back.

Element identities are short-lived across structural UI changes.

## Pixel-only applications

GLFW, Vulkan, games, canvas-heavy tools, remote-viewer surfaces, and other
custom-rendered apps may expose no useful accessibility tree. They may also be
missing from the runtime's semantic `list_apps` / `list_windows` inventory.

That does **not** make them uncontrollable.

If the surface is visibly present:

1. capture the visible screen;
2. locate it visually;
3. act with coordinates from the fresh image;
4. recapture after layout-changing actions;
5. foreground/select it with ordinary desktop gestures if obscured.

Semantic inventory is advisory. Visible pixels are authoritative for visible
pixel-only surfaces.

## Window geometry

This repository does not require WinRects or another GNOME Shell geometry
helper. A missing rectangle in the runtime driver is a reason to switch evidence
surfaces, not a reason to modify GNOME Shell.

## Installed web apps

The identity resolver distinguishes standalone browser-backed applications from
generic browser chrome using:

- live app/window identity;
- desktop file IDs;
- `StartupWMClass`;
- `--app-id=`;
- `--app=`;
- browser-engine hints.

The launcher inventory is cached to keep repeated routing cheap.

## Input

Semantic/background input is preferred. Coordinate delivery is appropriate for
pixel-only surfaces. Foreground delivery is an escalation, not a default.

`ydotool` remains an explicit final fallback through `/dev/uinput`; it is not
required for portal capture.

## Multi-display

The ScreenCast portal selects a monitor source. The returned stream represents
that monitor and may include compositor-space metadata. Do not assume physical
pixel coordinates and compositor logical coordinates are identical under
fractional scaling.

Coordinate actions must come from the latest relevant image/target geometry.

## Permission boundaries

- First ScreenCast use may require GNOME monitor-sharing consent.
- Revoked/invalid restore permission may cause the chooser to reappear.
- Cancelling that chooser is a real denial and halts the capture chain.
- Privileged host changes use narrow graphical PolicyKit prompts.
- Foreground input is visible and should follow the user's active-task intent.

## Completion proof

A computer-use action is complete when the requested postcondition is proven by
structured read-back or fresh evidence appropriate to the target. A ceremonial
extra screenshot is unnecessary when stronger proof already exists.
