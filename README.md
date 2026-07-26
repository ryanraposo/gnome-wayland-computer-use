# gnome-wayland-computer-use

```
      __
 (___()'`;
 /,    /`
 "--\
```

**Skill + extension** for enabling `computer_use` on GNOME Wayland.

- **`SKILL.md`** — ⚕ agent skill (auto-discovered by [Hermes](https://github.com/nousresearch/hermes-agent)): detects Wayland vs X11, installs `winrects@cua`, fixes `computer_use`.
- **`install.sh` + `extension/`** — standalone installer + bundled `winrects@cua` GNOME Shell extension (zero external deps).

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
# then log out & back in
```

Exposes `org.cua.WinRects` on D-Bus (`GetRects`, `Capture`, `Activate`, `MoveCursor`, `ClickPulse`). Without it, native Wayland apps are invisible to cua-driver.

**Credit:** `winrects@cua` by [trycua/cua](https://github.com/trycua/cua) (Apache 2.0). This repo bundles it with a skill layer on top.
