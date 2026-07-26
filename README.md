<div align="center">
<pre>
▄ ▄▄ ▄▄▄▄
   ▄▀ 0x0 ▀▄
    █  ───  █
</pre>
</div>

# gnome-wayland-computer-use

Call it once or in place of `computer_use`. Auto-fixes the stack (extension install, systemd env vars, cua-driver version), then runs `computer_use` and returns results.

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
# then log out & back in
```

### What's in here

- **`SKILL.md`**   ⚕ agent skill: actionable diagnostic/fix playbook the agent executes step by step. Always ends by calling `computer_use`. Replaces bare `computer_use` calls.
- **`install.sh`**   one-shot installer: installs extension, fixes Hermes systemd env, checks cua-driver version.
- **`scripts/diagnose.sh`**   CLI diagnostic for the full stack.
- **`scripts/fix-hermes-env.sh`**   standalone fix for the systemd env var trap.
- **`extension/`**   bundled `winrects@cua` GNOME Shell extension (exposes `org.cua.WinRects` D-Bus interface).

**Credit:** `winrects@cua` by [trycua/cua](https://github.com/trycua/cua) (Apache 2.0). This repo bundles it with a skill layer on top.
