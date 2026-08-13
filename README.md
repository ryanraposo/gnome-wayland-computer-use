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

**Accessibility when semantics exist. Pixels when they do not. Native portals for the screen.**

[Install](#install) · [Architecture](#architecture) · [Capture](#native-screen-capture) · [Diagnose](#diagnose)
</div>

---

Linux desktop automation tends to fail in two opposite ways: it either pretends
Wayland is X11, or it grows a pile of compositor-specific helpers until the
helpers become the product.

This project does neither.

It gives capable agents a GNOME/Wayland operating contract built around the
surfaces the desktop already provides: AT-SPI for accessible applications, XDG
ScreenCast/Screenshot portals + PipeWire for pixels, and explicit input recovery
when semantic delivery cannot finish the job.

## Architecture

| Need | Primary surface | Recovery |
|---|---|---|
| Read/act on accessible UI | AT-SPI through the runtime driver | pixels → foreground |
| Capture the visible display | XDG ScreenCast + PipeWire | Screenshot portal → legacy GNOME capture → Shift+Print |
| Identify installed web apps | live identity + cached desktop launchers | generic browser identity |
| Operate pixel-only GLFW/Vulkan/canvas UI | visible-screen pixels + coordinates | ordinary foreground/window selection |
| Last-resort synthetic input | runtime driver | `/dev/uinput` + `ydotool` |
| Privileged host action | narrow graphical `pkexec` | explicit manual recovery |

**There is no GNOME Shell extension in the architecture.**

Older releases of this repository shipped
`desktop-capture@gnome-wayland-computer-use` and accidentally coupled a desktop
fallback to a separate WinRects helper. Version 2.3 retires the project-owned
capture extension during install and does not require WinRects. Missing semantic
window geometry now degrades to pixels instead of another Shell helper.

## Why this matters

A GLFW/Vulkan renderer can be plainly visible and still expose no useful AT-SPI
surface. On such an app, an empty `list_windows` result is not proof that the
window is absent. The visible screen is the authoritative evidence surface.

Conversely, an accessible text field does not need a screenshot between every
click and keystroke. The skill keeps deterministic semantic actions together
and observes again only when the next decision depends on changed state.

That combination is the point: **semantic where possible, visual where
necessary, neither confused for the other.**

## Install

Run as the logged-in desktop user:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

The installer prefers Hermes when it is present; otherwise it installs the
shared Agent Skill stack under `~/.agents/skills/`.

```text
--hermes      require Hermes integration
--agent-only  install the shared stack without Hermes
--compat      relax the GNOME/Wayland environment preflight
--unattended  mark automated execution
```

The host stack enables toolkit accessibility, installs the shared skill and
capture helper, configures the explicit `/dev/uinput` fallback, and connects the
Hermes runtime when selected.

A session sign-out/sign-in is needed only when the installer newly adds the user
to the `input` group. **Capture itself does not require a session reload or a
Shell extension.**

## Native screen capture

```bash
CAPTURE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/capture.sh"

"$CAPTURE" --screen /tmp/screen.png
"$CAPTURE" --timing --screen /tmp/screen.png
"$CAPTURE" --media --screen
```

`--desktop` remains accepted for old callers, but it is now an alias for the
real visible display. The helper no longer hides windows to manufacture a
special wallpaper/icons layer.

### Capture order

1. **XDG ScreenCast + PipeWire** — the hot path. The portal selects one monitor,
   and on portal v4+ the helper requests `persist_mode=2`. A restore token is
   stored under the user's state directory and rotated after every successful
   restoration.
2. **XDG Screenshot portal** — one-shot recovery path.
3. **`gnome-screenshot`** — compatibility for older GNOME releases only. GNOME
   49+ is skipped because its legacy Shell path is no longer a reliable surface.
4. **Shift+Print through `ydotool`** — final hardware-level recovery.

The first ScreenCast capture may show GNOME's monitor-sharing chooser. That is a
real permission boundary, not installer ceremony. Once persistence is granted,
subsequent captures restore the selected source instead of rebuilding the
permission decision from scratch.

If the user cancels the chooser, the helper stops rather than surprising them
with a second permission UI.

Writes are atomic: a failed capture never replaces an existing output file.
`--timing` emits `capture_elapsed_ms=N` on stderr.

## Wallpaper versus screen

If the user wants **what is currently visible**, capture the screen.

If the user wants **the wallpaper image itself**, resolve GNOME's configured
background asset (`org.gnome.desktop.background`) instead of hiding windows and
calling that a screenshot.

If desktop icons are supplied by another extension, they are simply visible
screen content. This project does not couple itself to that extension's private
geometry or scene graph.

## Accessible apps versus pixel-only apps

For accessible applications, begin with the runtime's AX-only inspection.
Escalate to pixels only when layout, canvas content, or inaccessible controls
make pixels relevant.

For GLFW, Vulkan, games, canvas-heavy applications, remote-viewer surfaces, or
other custom-rendered windows:

1. capture the visible display;
2. locate the surface visually;
3. use coordinate actions from that fresh image;
4. recapture after layout-changing operations;
5. use ordinary overview/Alt-Tab/foreground selection if the target is obscured.

Do not repeatedly probe AT-SPI for a surface that has no accessibility contract,
and do not install a Shell helper just to make semantic inventory look complete.

## Installed web apps stay apps

Standalone Chrome/Chromium/Brave/Edge/Firefox apps are resolved from live
identity first, then desktop IDs, `StartupWMClass`, and launcher flags such as
`--app-id=` / `--app=`.

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/app-identity.sh "ChatGPT"
```

The launcher inventory is cached briefly, so two PWAs backed by the same browser
remain distinct targets without paying for repeated discovery.

## Computer-use operating model

> **Route once → cheapest truthful evidence → semantic action span → verify at the next decision boundary.**

A confirmed field click can flow directly into complete text entry. A known
submit shortcut can follow verified typing. A structured driver verdict can be
verification when it actually proves the requested state.

Fresh evidence belongs at navigation, new dialogs, material list/layout changes,
stale element identity, pixel-only ambiguity, foreground escalation, or another
point where the next action depends on new UI state.

## Diagnose

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --json
```

The capture section proves:

- XDG ScreenCast portal — hot path
- PipeWire/GStreamer capture stack
- XDG Screenshot portal — recovery
- restore-token state — cached or first-capture pending
- legacy project capture extension — **absent is healthy**

It separately reports AT-SPI, the runtime integration, `/dev/uinput`, and
`ydotoold`.

A custom-rendered app missing from `list_windows` is not diagnosed as a broken
capture stack. Capture and semantic inventory are intentionally separate.

## Tests

```bash
bash ./tests/skill-ux.sh
bash ./tests/latency-routing.sh
./tests/run.sh
```

The regression suite protects portal-first capture, restore-token persistence,
atomic writes, cancellation behavior, the absence of Shell-helper dependencies,
pixel-only recovery guidance, installed-web-app identity, and the runtime skill
contract.

## Operational notes

- Ubuntu 26.04 / GNOME 50 is the production target.
- XDG ScreenCast v4+ supplies persistent restore tokens; newer portal versions
  remain compatible with the node-ID stream path used here.
- Accessibility quality depends on the target application's AT-SPI support.
- `ydotool` is a last resort, not the screen-capture architecture.
- The runtime may have its own imperfect window inventory. The skill treats it
  as advisory and uses pixels for visible custom surfaces.
- Hermes skill archives remain under
  `~/.hermes/backups/gnome-wayland-computer-use/` and can be restored by
  teardown.

## Uninstall

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/teardown.sh
```

Teardown removes managed services/routing/skills and restores archived Hermes
skills. It also cleans up this project's legacy capture extension if an old
install left one behind. It does not touch unrelated Shell extensions such as a
user-installed WinRects helper.

## Repository map

| Path | Purpose |
|---|---|
| `install.sh` | self-contained local and curl-pipe installer |
| `SKILL.md` | Hermes-native computer-use contract |
| `runtimes/openai/SKILL.md` | portable/OpenAI-native contract |
| `scripts/capture.sh` | ScreenCast/PipeWire capture + recovery ladder |
| `scripts/app-identity.sh` | cached browser/PWA/Electron identity resolver |
| `scripts/diagnose.sh` | human + JSON host diagnostics |
| `scripts/serve.sh` | Hermes `cua-driver` backend wrapper |
| `scripts/teardown.sh` | managed removal and skill restoration |
| `lib/checks.sh` | shared health predicates |
| `CAPABILITIES.md` | capability map and degradation rules |
| `PERF_NOTES.md` | latency model and measurement guidance |
| `references/skill-ux-contract.md` | workflow/authorization proof contract |
| `tests/` | regression, routing, and skill UX guards |
