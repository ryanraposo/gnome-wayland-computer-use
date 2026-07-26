<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
</pre>
</div>

# gnome-wayland-computer-use

Diagnoses and fixes 0x0 captures from `computer_use` on GNOME Wayland.
Installs the required `winrects@cua` GNOME Shell extension, checks or
installs `cua-driver`, fixes Hermes systemd env vars, verifies D-Bus
capture, then runs `computer_use`.

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
# then restart GNOME Shell or log out/in
```

### What's in here

- **`SKILL.md`** — agent skill: diagnostic/fix playbook the agent executes step by step. Installs dependencies, fixes env, calls `computer_use`.
- **`install.sh`** — one-shot installer: cua-driver, extension, Hermes env fix.
- **`scripts/diagnose.sh`** — CLI diagnostic for the full stack.
- **`scripts/fix-hermes-env.sh`** — standalone fix for systemd env var trap.
- **`extension/`** — bundled `winrects@cua` GNOME Shell extension (exposes `org.cua.WinRects` D-Bus interface).

**Credit:** `winrects@cua` by [trycua/cua](https://github.com/trycua/cua) (Apache 2.0). This repo bundles it with a skill layer on top.
