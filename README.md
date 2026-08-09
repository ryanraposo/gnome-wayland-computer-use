<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
    █  ███  █
     ▀▀   ▀▀
</pre>

# gnome-wayland-computer-use

Low-latency accessibility actions. Desktop-aware screenshots. Verified recovery
paths. One installer for the full stack.

[Install](#install) · [Capabilities](#capabilities) · [Performance](PERF_NOTES.md) · [How it works](#how-it-works) ·
[Diagnose](#diagnose) · [Uninstall](#uninstall)
</div>

---

Agents have variable success using Linux. This project makes computer use dependable on the most popular Linux desktop out there, **Ubuntu 26**.

## Capabilities

**[Explore the complete capability map →](CAPABILITIES.md)**

- Cached application and window discovery, including installed-web-app identity
- AX-first inspection with vision and SOM only when pixels are actually needed
- Background-first semantic input in useful action spans
- Clicks, full-text typing, shortcuts, forms, menus, sliders, scrolling, drag-and-drop, dialogs, and file choosers
- Multi-window and multi-display operation
- Compositor-aware desktop and screen capture with timing diagnostics
- Decision-boundary verification instead of ritual post-action recapture
- Structured recovery through pixels, foreground delivery, and `/dev/uinput`
- PolicyKit privilege handling, diagnostics, teardown, and native Hermes and OpenAI integrations

> [!TIP]
> **Top secret:** tell any capable agent about this repository and ask it to install the skill. The repo’s agent-facing instructions help it choose the right runtime, preserve existing setup, and verify the install.

- AT-SPI actions target accessible widgets and editable text without raising
  windows when the application supports it.
- Browser-backed standalone apps are resolved as their own app targets when
  desktop/window identity or launcher flags distinguish them from browser chrome.
- “Desktop” means the wallpaper and desktop-icons layer; “screen” means the
  visible display, including windows.
- The preferred desktop capture path runs inside GNOME Shell and proves that
  focus, workspace, and window state did not change.
- Compatibility input is explicit, last-resort, and backed by `/dev/uinput`
  through Ubuntu's `ydotool`.
- When Hermes is present, its existing computer-use and learned screenshot
  skills are archived before replacement and can be restored by teardown.

> [!IMPORTANT]
> The no-foreground guarantee applies to supported AT-SPI actions and the primary
> compositor capture path. Pixel/input fallbacks may briefly affect the visible
> desktop; the desktop fallback restores Show Desktop and verifies window state
> before reporting success.

## Install

Run one command as your normal desktop user—**not with `sudo`**:

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

The installer prefers Hermes automatically:

- **Hermes on `PATH`** — installs the full Hermes override, routing, `cua-driver`
  service, and the portable Agent Skill.
- **No Hermes** — installs the same GNOME host stack and a portable
  `.agents/skills/` integration for the invoking agent. It does not create or
  modify `~/.hermes`.

You need an active GNOME Wayland session, network access, and permission to
configure packages, `/dev/uinput`, and input-group access. The installer prefers
`pkexec` so each administrative command gets a graphical PolicyKit prompt; it
falls back to `sudo` when PolicyKit is unavailable. It never runs the whole
installer or a general-purpose shell as root.

Want to inspect it first?

```bash
curl -fsSLO https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh
less install.sh
bash install.sh
```

| Option | Effect |
|---|---|
| `--hermes` | Require Hermes and fail before host changes if it is unavailable |
| `--agent-only` | Skip Hermes even when it is installed |
| `--unattended` | Mark automated execution; implied when input is piped |
| `--compat` | Continue outside a GNOME Wayland session |

`--compat` relaxes the environment check; it does not make the GNOME-specific
capture extension portable to other desktops. PolicyKit or `sudo` may still
request approval during unattended installation.

### Then

Follow the installer's `Next:` line. If it requests a session reload, sign out
of GNOME and back in once, then start a new Hermes or agent session. No reboot
required. Until then, desktop capture can use the verified Show Desktop →
capture → restore path.

The Agent Skills and Hermes payloads are authored independently for their
native tool conventions. First-use computer-use routing reads only an existing
cached `VERSION` result and never waits on the network. Run
`scripts/check-update.sh --force` when you actually want to refresh it.

## Computer-use operating model

The fast path is:

> **Route once → cheapest useful evidence → semantic action span → verify at the next decision boundary.**

A known app/window target is reused instead of rediscovered. AX-only inspection
is preferred when text, roles, and state are enough; vision is for image-only
reasoning; SOM is reserved for tasks that genuinely need pixels plus element
grounding.

Deterministic input stays together. A confirmed field click can be followed by
one complete typing action without an intervening screenshot; a known submit
hotkey can follow verified typing when the next action does not depend on newly
rendered state. Semantic `set_value` is preferred over opening and re-reading a
menu. Waits are for real asynchronous transitions, not pacing.

Fresh evidence belongs at actual decision boundaries: navigation, new dialogs,
material list changes, stale element identity, canvas/visual ambiguity, focus
escalation, or any step where the next action depends on the new UI. A
structured driver verdict that directly proves the requested state is already
verification and does not need a ceremonial screenshot afterward.

The skill owns the complete workflow: route → observe → act → verify → recover
or complete. It infers reversible background-first defaults, asks only
questions that change the decision, previews consequential effects at their
real authorization boundary, and finishes from observable proof.

The Hermes payload documents its complete SOM/AX action vocabulary and
structured background → pixel → foreground escalation contract. The OpenAI
payload follows the runtime's live native tool schema instead of inventing
Hermes arguments. Both cover forms, menus, dialogs, file choosers, nested
scrolling, drag-and-drop, multi-display coordinates, safety, and recovery.

For an explicitly authorized package install, the preferred privilege boundary
is a direct graphical prompt:

```bash
pkexec apt-get install -y PACKAGE...
```

The agent should explain the change, run the smallest command, and verify the
result without privilege. It should never type the user's password or open a
root terminal.

## Installed web apps vs browsers

When a Chrome/Chromium/Brave/Edge/Firefox-backed window has standalone app
identity, the skill treats it as that installed web app instead of collapsing
it into the generic browser. Live app/window identity wins. If ambiguity
remains, the installed launcher resolver can inspect desktop IDs,
`StartupWMClass`, `--app-id=`, and `--app=` without taking another screenshot:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/app-identity.sh "ChatGPT"
```

The resolver caches its launcher inventory briefly in the runtime directory.
It understands direct browser launchers plus wrapped and Flatpak-style commands,
so two PWAs using the same browser engine remain separate targets when their
launcher/window identities differ. Electron applications remain native app
targets when the desktop/runtime exposes their distinct identity.

## Intent-aware capture

| What you ask for | What you get | Default path |
|---|---|---|
| “Capture my desktop”, wallpaper, or desktop icons | The GNOME desktop layer without covering app windows | GNOME Shell compositor extension |
| “Capture my screen” or “what I’m looking at” | The current visible display, including windows | Screenshot portal |
| Click, type, or inspect an app | Accessibility tree and stable widget actions where supported | AT-SPI through `cua-driver` |

The capture helper also works directly:

```bash
CAPTURE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/capture.sh"

"$CAPTURE" --desktop /tmp/desktop.png
"$CAPTURE" --screen /tmp/screen.png
```

Writes are atomic: a failed attempt does not replace an existing output file.
Hermes can add `--media` to choose a timestamped path and emit its `MEDIA:`
attachment marker. Add `--timing` to emit `capture_elapsed_ms=N` on stderr.

## How it works

The installer configures five layers:

1. **Session checks** — detects GNOME and Wayland and reports mismatches.
2. **Accessibility** — enables GNOME toolkit accessibility and starts the AT-SPI
   bus.
3. **Capture and routing** — installs the GNOME Shell extension, cached installed-app
   identity resolver, and portable Agent Skill. When Hermes is selected, it also
   installs the exact canonical `computer-use` override and always-loaded
   desktop-versus-screen routing.
4. **Input recovery** — installs the Ubuntu capture dependencies, loads
   `/dev/uinput`, grants the desktop user access, and starts `ydotoold` with a
   short managed restart delay.
5. **Runtime** — with Hermes, installs and health-checks a persistent
   native-Wayland `cua-driver` service with fast readiness polling. Other agents
   keep their own native tool schema and use the shared host helpers directly.

### Capture order

**Desktop**

1. GNOME Shell captures the desktop layer while app-window actors are excluded
   from the offscreen capture. It rejects the result if focus, workspace, or
   window state changed.
2. The compatibility path toggles Show Desktop, takes one full-screen capture,
   restores the prior state, and compares compositor window state. Screenshot and
   restoration readiness are polled rather than padded with fixed animation sleeps.

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
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
```

For machine-readable output:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh --json
```

For latency and routing diagnosis:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/app-identity.sh "ChatGPT"
~/.agents/skills/gnome-wayland-computer-use/scripts/capture.sh --timing --screen /tmp/screen.png
```

From a repository checkout:

```bash
bash ./tests/skill-ux.sh
bash ./tests/latency-routing.sh
./tests/run.sh
```

The regression suite covers routing, capture order, portal cancellation, atomic
failure behavior, local and curl-pipe installation, skill preservation,
teardown restoration, runtime authority, and the sub-60-character description
contract. The latency guard additionally covers cache-only first use, browser/PWA
identity including wrapped launchers, published-site consistency, semantic-action
spans, decision-boundary verification, fast screenshot fallbacks, and service recovery.

## Operational notes

- The supported GNOME Shell extension metadata covers Shell 45–50; Ubuntu 26.04
  is the production target.
- GNOME 49+ blocks the legacy `gnome-screenshot` D-Bus path, so the helper skips
  it and uses the Screenshot portal.
- Accessibility quality depends on the target app's AT-SPI implementation.
  Electron apps may need accessibility enabled by their launcher.
- Synthetic input requires a GNOME session reload after first joining the
  `input` group.
- In Hermes mode, the installer may modify `~/.hermes/SOUL.md`, but only inside
  a marked managed block. Existing content is preserved.
- Hermes skill archives live under
  `~/.hermes/backups/gnome-wayland-computer-use/`.

## Uninstall

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/teardown.sh
```

Teardown interactively removes managed services, routing, skills, the udev rule,
and the Shell extension, and offers to restore every archived skill. It leaves
Ubuntu packages and input-group membership as explicit manual cleanup choices.
Use `--force` only when you want every managed teardown prompt accepted.

## Repository map

| Path | Purpose |
|---|---|
| `install.sh` | Self-contained local and curl-pipe installer |
| `index.html` | Published landing page; kept aligned with the runtime latency contract |
| `AGENTS.md` | Install, use, and maintenance funnel for repository-aware agents |
| `SKILL.md` | Hermes-native `computer-use` skill |
| `runtimes/openai/SKILL.md` | OpenAI-native Agent Skill payload |
| `agents/openai.yaml` | OpenAI skill-list metadata and implicit-trigger policy |
| `references/skill-ux-contract.md` | Workflow phases, decisions, mutations, and completion proof |
| `CAPABILITIES.md` | Complete computer-use capability spread and operating model |
| `PERF_NOTES.md` | Separated latency budgets, regression evidence, and measurement guidance |
| `VERSION` | Published skill-bundle release version |
| `gnome-shell-extension/` | Focus-free desktop-layer capture service |
| `lib/checks.sh` | Shared environment and health checks |
| `scripts/app-identity.sh` | Cached installed-browser/PWA/Electron launcher identity resolver |
| `scripts/capture.sh` | Atomic desktop/screen capture router with timing diagnostics |
| `scripts/check-update.sh` | Cache-only hot-path and explicit cached release update check |
| `scripts/diagnose.sh` | Human and JSON diagnostics |
| `scripts/serve.sh` | Persistent `cua-driver` backend |
| `scripts/teardown.sh` | Managed removal and skill restoration |
| `tests/skill-ux.sh` | Constitutional and metadata regression checks |
| `tests/latency-routing.sh` | End-to-end latency, PWA routing, site, and recovery guards |
| `tests/run.sh` | End-to-end shell regression suite |
| `assets/` | Landing-page and repository social artwork |
