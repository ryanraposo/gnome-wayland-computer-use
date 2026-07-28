<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
</pre>

# gnome-wayland-computer-use

Reliable accessibility actions. Desktop-aware screenshots. Verified recovery
paths. One installer for the full stack.

[Install](#install) · [How it works](#how-it-works) ·
[Diagnose](#diagnose) · [Uninstall](#uninstall)
</div>

---

Agents have variable success using linux. This project makes that foundation
dependable on the most popular linux desktop out there, **Ubuntu 26**:

- AT-SPI actions target accessible widgets and editable text without raising
  windows when the application supports it.
- “Desktop” means the wallpaper and desktop-icons layer; “screen” means the
  visible display, including windows.
- The preferred desktop capture path runs inside GNOME Shell and proves that
  focus, workspace, and window state did not change.
- Compatibility input is explicit, last-resort, and backed by `/dev/uinput`
  through Ubuntu's `ydotool`.
- Existing Hermes computer-use and learned screenshot skills are archived before
  replacement and can be restored by teardown.

> [!IMPORTANT]
> The no-foreground guarantee applies to supported AT-SPI actions and the primary
> compositor capture path. Pixel/input fallbacks may briefly affect the visible
> desktop; the desktop fallback restores Show Desktop and verifies window state
> before reporting success.

## Install

You need:

- An active GNOME Wayland session
- `sudo` access for Ubuntu packages, the `uinput` rule, and input-group setup
- a network connection

Run the installer as your normal desktop user—**not with `sudo`**:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

Prefer to inspect it first?

```bash
curl -fsSLO https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh
less install.sh
bash install.sh
```

The installer is idempotent and accepts:

```text
--unattended  Mark automated execution; implied when input is piped
--compat      Continue when the current session is not GNOME Wayland
```

`--compat` relaxes the environment check; it does not make the GNOME-specific
capture extension portable to other desktops. `sudo` may still request a
password during unattended installation.

### First-run handoff

The installer prints the exact next step. If it added input-group membership or
could not hot-load the Shell extension, sign out of the **GNOME session** and
sign back in once, then start a new Hermes session. Until that reload, desktop
capture can use the verified Show Desktop → capture → restore compatibility
path.

## Intent-aware capture

| What you ask for | What you get | Default path |
|---|---|---|
| “Capture my desktop”, wallpaper, or desktop icons | The GNOME desktop layer without covering app windows | GNOME Shell compositor extension |
| “Capture my screen” or “what I’m looking at” | The current visible display, including windows | Screenshot portal |
| Click, type, or inspect an app | Accessibility tree and stable widget actions where supported | AT-SPI through `cua-driver` |

The capture helper also works directly:

```bash
CAPTURE="$HOME/.hermes/skills/computer-use/scripts/capture.sh"

"$CAPTURE" --desktop /tmp/desktop.png
"$CAPTURE" --screen /tmp/screen.png
"$CAPTURE" --media
```

Writes are atomic: a failed attempt does not replace an existing output file.
`--media` chooses a timestamped path and emits the `MEDIA:` attachment marker
Hermes expects.

## How it works

The installer configures five layers:

1. **Session checks** — detects GNOME and Wayland and reports mismatches.
2. **Accessibility** — enables GNOME toolkit accessibility and starts the AT-SPI
   bus.
3. **Capture and routing** — installs the GNOME Shell extension, the reusable
   agent skill, the Hermes `computer-use` override, and an always-loaded
   desktop-versus-screen routing rule.
4. **Input recovery** — installs the Ubuntu capture dependencies, loads
   `/dev/uinput`, grants the desktop user access, and starts `ydotoold`.
5. **Backend** — installs `cua-driver` if necessary and keeps it running
   as a user service with native Wayland support.

### Capture order

**Desktop**

1. GNOME Shell captures the desktop layer while app-window actors are excluded
   from the offscreen capture. It rejects the result if focus, workspace, or
   window state changed.
2. The compatibility path toggles Show Desktop, takes one full-screen capture,
   restores the prior state, and compares compositor window state.

**Visible screen**

1. `gnome-screenshot --file` on GNOME releases where it is supported
2. the non-interactive `org.freedesktop.portal.Screenshot` request
3. GNOME's direct full-screen shortcut through `ydotool`

Portal cancellation stops the chain instead of opening another capture UI.
ScreenCast/PipeWire is diagnostic-only because it can show a sharing chooser;
opt in with `GNOME_WAYLAND_ENABLE_SCREENCAST_FALLBACK=1`.

## Diagnose

After installation:

```bash
~/.hermes/skills/computer-use/scripts/diagnose.sh
```

For machine-readable output:

```bash
~/.hermes/skills/computer-use/scripts/diagnose.sh --json
```

From a repository checkout:

```bash
./tests/run.sh
```

The regression suite covers routing, capture order, portal cancellation, atomic
failure behavior, local and curl-pipe installation, skill preservation, and
teardown restoration.

## Operational notes

- The supported GNOME Shell extension metadata covers Shell 45–50; Ubuntu 26.04
  is the production target.
- GNOME 49+ blocks the legacy `gnome-screenshot` D-Bus path, so the helper skips
  it and uses the Screenshot portal.
- Accessibility quality depends on the target app's AT-SPI implementation.
  Electron apps may need accessibility enabled by their launcher.
- Synthetic input requires a GNOME session reload after first joining the
  `input` group.
- The installer may modify `~/.hermes/SOUL.md`, but only inside a marked managed
  block. Existing content is preserved.
- Archived skills live under
  `~/.hermes/backups/gnome-wayland-computer-use/`.

## Uninstall

```bash
~/.hermes/skills/computer-use/scripts/teardown.sh
```

Teardown interactively removes managed services, routing, skills, the udev rule,
and the Shell extension, and offers to restore every archived skill. It leaves
Ubuntu packages and input-group membership as explicit manual cleanup choices.
Use `--force` only when you want every managed teardown prompt accepted.

## Repository map

| Path | Purpose |
|---|---|
| `install.sh` | Self-contained local and curl-pipe installer |
| `SKILL.md` | Reusable GNOME Wayland agent guidance |
| `gnome-shell-extension/` | Focus-free desktop-layer capture service |
| `lib/checks.sh` | Shared environment and health checks |
| `scripts/capture.sh` | Atomic desktop/screen capture router |
| `scripts/diagnose.sh` | Human and JSON diagnostics |
| `scripts/serve.sh` | Persistent `cua-driver` backend |
| `scripts/teardown.sh` | Managed removal and skill restoration |
| `tests/run.sh` | End-to-end shell regression suite |
| `assets/` | Landing-page and repository social artwork |
