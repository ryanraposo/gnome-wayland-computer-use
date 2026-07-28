<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
</pre>

# gnome-wayland-computer-use

**Computer use for GNOME Wayland.**

Background-safe actions. Desktop-aware screenshots. Fallbacks that prove they
put everything back. One command installs the stack.

[Install](#install) · [How it works](#how-it-works) ·
[Diagnose](#diagnose) · [Uninstall](#uninstall)
</div>

---

Hermes already knows how to operate a desktop. This makes it dependable on
**Ubuntu 26.04, GNOME, and Wayland**:

- **Act without barging in.** AT-SPI targets accessible controls and editable
  text without raising supported windows.
- **Capture what was asked for.** “Desktop” means wallpaper and icons; “screen”
  means the visible display, windows included.
- **Prove nothing moved.** The primary desktop capture verifies focus, workspace,
  and window state before it reports success.
- **Recover safely.** Synthetic input is an explicit last resort, and displaced
  Hermes skills are archived for teardown to restore.

> [!IMPORTANT]
> The no-foreground guarantee applies to supported AT-SPI actions and the primary
> compositor capture path. Pixel/input fallbacks may briefly affect the visible
> desktop; the desktop fallback restores Show Desktop and verifies window state
> before reporting success.

## Install

Run this as your normal desktop user—**not with `sudo`**:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

That is the install. It checks the session, fetches missing packages, preserves
existing Hermes skills, and asks for `sudo` only when a system change needs it.
Safe to rerun.

It expects:

- Ubuntu 26.04 in an active GNOME Wayland session
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) on `PATH` as
  `hermes`
- network access and permission to use `sudo`

Handing the job to another assistant? Point it at this repository and say
“install it.” From a checkout it should run `./install.sh` as your desktop user
and relay the final `Next:` instruction. The installing assistant does not need
to be Hermes.

Want to inspect the script first?

```bash
curl -fsSLO https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh
less install.sh
bash install.sh
```

| Option | Effect |
|---|---|
| `--unattended` | Marks automated execution; implied when input is piped |
| `--compat` | Continues when the current session is not GNOME Wayland |

`--compat` relaxes the environment check; it does not make the GNOME-specific
capture extension portable to other desktops. `sudo` may still request a
password during unattended installation.

### Then

Follow the installer's `Next:` line. If it requests a session reload, sign out
of GNOME and back in once, then start a new Hermes session. No reboot required.
Until then, desktop capture can use the verified Show Desktop → capture →
restore path.

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
3. **Capture and routing** — installs the GNOME Shell extension, the Hermes
   `computer-use` skill, derives Agent Skills-standard discovery metadata for
   the shared `.agents/skills/` location, and activates an always-loaded
   desktop-versus-screen routing rule.
4. **Input recovery** — installs the Ubuntu capture dependencies, loads
   `/dev/uinput`, grants the desktop user access, and starts `ydotoold`.
5. **Hermes backend** — installs `cua-driver` if necessary and keeps it running
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

The regression suite covers routing, capture order, portal cancellation,
atomic failure behavior, local and curl-pipe installation, skill preservation,
and teardown restoration.

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
| `SKILL.md` | Sole Hermes-authored `computer-use` skill and intent routing |
| `gnome-shell-extension/` | Focus-free desktop-layer capture service |
| `lib/checks.sh` | Shared environment and health checks |
| `scripts/capture.sh` | Atomic desktop/screen capture router |
| `scripts/diagnose.sh` | Human and JSON diagnostics |
| `scripts/serve.sh` | Persistent `cua-driver` backend |
| `scripts/teardown.sh` | Managed removal and skill restoration |
| `tests/run.sh` | End-to-end shell regression suite |
| `assets/` | Landing-page and repository social artwork |
