<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
</pre>
</div>

# gnome-wayland-computer-use

**Just works.** One `curl | bash` enables GNOME Wayland desktop automation for any AI agent. Enables the accessibility bus, starts `at-spi-bus-launcher`, sets up `/dev/uinput` access, and installs the skill — all in four steps. Agent reads the skill, agent uses the desktop. No config files to edit, no daemons to restart, no logout required.

**Isn't annoying.** AT-SPI2 AX Rung (primary path) never steals focus, never promotes windows, never interrupts the user. `insertText` writes directly to memory buffers. `doAction` invokes widgets without touching window stacking. The user keeps working — the agent works around them. Focus-stealing `ydotool` fallback is last resort only.

**Zero third-party dependencies.** No cua-driver, no proprietary daemon, no GNOME Shell extension to break on update, no npm/pip/cargo install. Just what GNOME already ships: `gsettings`, `at-spi-bus-launcher`, `systemd --user`, `ydotool`, `/dev/uinput`. One markdown file the agent already reads. That's the whole stack.

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

### What's in here

- **`SKILL.md`** — agent skill with concrete D-Bus commands for capture, text entry, and clicks
- **`lib/checks.sh`** — shared validation library sourced by all scripts
- **`install.sh`** — one-shot installer (4 steps)
- **`scripts/diagnose.sh`** — CLI diagnostic with `--json` output for programmatic use
- **`scripts/teardown.sh`** — full uninstall
