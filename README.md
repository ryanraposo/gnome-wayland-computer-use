<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
</pre>
</div>

# gnome-wayland-computer-use

**Reliable Hermes computer use on Ubuntu 26.04 GNOME Wayland.** One command installs the GNOME-native accessibility, capture, and input stack; fixes screenshot intent routing; and keeps the backend ready.

**Designed not to interrupt you.** The primary AX path uses AT-SPI editable-text and widget actions without promoting application windows. Desktop-layer capture verifies that focus, workspace, and window state are identical before and after. Synthetic keyboard/mouse input is reserved for compatibility recovery.

**Desktop and screen mean different things.**

| Request | Captured content | Primary path |
|---|---|---|
| “Capture my desktop/wallpaper/icons” | The underlying GNOME desktop layer, without covering app windows | GNOME Shell compositor extension with state proof |
| “Capture my screen/what I’m looking at” | The current visible display, including windows | Non-interactive Screenshot portal |

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

After the first installation, sign out of the GNOME session and sign back in
once. This loads the desktop-layer capture extension and applies input-group
membership if the installer added it. Then start a new Hermes session. Until
the GNOME session reload, desktop capture uses the verified compatibility path:
Show Desktop → capture → restore → compare window state.

## How does it work?

1. **Checks the desktop** — detects GNOME and Wayland, warning without aborting if the environment differs.
2. **Enables accessibility** — turns on GNOME toolkit accessibility, starts the AT-SPI bus, and installs missing Ubuntu capture/input dependencies.
3. **Installs capture and routing** — queues the GNOME Shell desktop-layer extension, installs the local Hermes `computer-use` override, and teaches Hermes the desktop-versus-screen distinction. Existing `computer-use` skills and conflicting learned screenshot skills are archived outside Hermes's active skill path, never discarded.
4. **Configures input fallback** — loads `/dev/uinput`, grants the active desktop user access, and enables Ubuntu's packaged `ydotool.service`.
5. **Connects Hermes** — installs cua-driver when needed, enables native Wayland support, and starts a persistent user service for Hermes's `computer_use` tool.

This routing migration also handles machines where Hermes has already tried and learned the wrong screenshot path (`grim`, `slurp`, `gnome-screenshot`, or the blocked Shell D-Bus API). The teardown helper restores every displaced skill from `~/.hermes/backups/gnome-wayland-computer-use/`.

Desktop capture is atomic: the primary compositor extension temporarily excludes
normal app-window actors from its offscreen capture and rejects success unless
focus, workspace, and window state match before and after. The compatibility
path briefly toggles Show Desktop, takes exactly one full-screen image, restores
the windows, and compares compositor state.

Visible-screen capture tries `gnome-screenshot` only on supported GNOME releases,
then the non-interactive Screenshot portal, then direct `Shift+Print`.
ScreenCast/PipeWire remains available only for diagnostics via
`GNOME_WAYLAND_ENABLE_SCREENCAST_FALLBACK=1`; it is disabled by default because
it can open a recurring screen-sharing chooser.

The installer waits for the Hermes backend to report healthy before succeeding.
Follow any one-time GNOME session reload instruction it prints, then start a new
Hermes session.

### Capture helpers

```bash
# Wallpaper and desktop icons; this is the default mode.
~/.hermes/skills/computer-use/scripts/capture.sh --desktop /tmp/desktop.png

# The currently visible display, including windows.
~/.hermes/skills/computer-use/scripts/capture.sh --screen /tmp/screen.png

# Let Hermes emit its MEDIA attachment marker and choose a timestamped path.
~/.hermes/skills/computer-use/scripts/capture.sh --media
```

### What's in here

- **`SKILL.md`** — reusable GNOME Wayland dispatch and recovery guidance
- **`hermes/SKILL.md`** — Hermes `computer-use` override with explicit desktop/screen intent routing
- **`lib/checks.sh`** — shared validation library sourced by all scripts
- **`install.sh`** — one-shot installer (5 steps)
- **`gnome-shell-extension/`** — focus-free desktop-layer capture with before/after state proof
- **`scripts/capture.sh`** — atomic desktop and visible-screen capture with verified compatibility recovery
- **`scripts/diagnose.sh`** — CLI diagnostic with `--json` output for programmatic use
- **`scripts/serve.sh`** — persistent Hermes `computer_use` backend
- **`scripts/teardown.sh`** — guided removal plus restoration of archived user skills

Run the diagnostic after installation:

```bash
~/.hermes/skills/computer-use/scripts/diagnose.sh
```

Run the repository's regression suite:

```bash
./tests/run.sh
```

Run the guided teardown:

```bash
~/.hermes/skills/computer-use/scripts/teardown.sh
```

Teardown removes managed services, skills, routing, and the Shell extension.
It deliberately leaves input-group membership and installed Ubuntu packages as
manual cleanup choices and prints the corresponding commands.
