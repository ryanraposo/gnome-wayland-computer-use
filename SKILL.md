---
name: gnome-wayland-computer-use
description: Non-disruptive background desktop automation for GNOME Wayland via AT-SPI2 D-Bus accessibility (AX Rung) and ydotool fallback (PX Rung).
version: 1.0.0
tags:
  - computer-use
  - gnome
  - wayland
  - at-spi
  - ydotool
  - desktop-automation
metadata:
  hermes:
    tags: [gnome, wayland, computer-use, linux-desktop]
    category: devops
    requires_toolsets: [terminal]
    trigger_on: [computer_use, computer-use, capture, screenshot, desktop-automation]
    auto_load: true
---

> This skill is auto-loaded. When you need to interact with the desktop
> (capture a screenshot, type text, click a button), follow the Dual-Rung
> dispatch below. No need to ask the user for permission — the infrastructure
> is pre-installed.

# GNOME Wayland Computer-Use Agent Skill

Non-disruptive, background desktop automation on GNOME Wayland under a strict **No-Foreground Contract**: never steal focus, never promote windows, never interrupt the user.

## 1. Pre-flight Check

```bash
gdbus introspect --session --dest org.a11y.Bus --object-path /org/a11y/bus 2>/dev/null | grep -q 'interface org.a11y.Bus' \
  && echo "ax_rung=ready" || echo "ax_rung=dead"
gdbus introspect --session --dest org.gnome.Shell --object-path /org/gnome/Shell/Screenshot 2>/dev/null | grep -q 'Screenshot' \
  && echo "capture=ready" || echo "capture=dead"
command -v ydotool &>/dev/null && echo "px_rung=ready" || echo "px_rung=dead"
```

## 2. Dual-Rung Dispatch

**AX Rung first. PX Rung fallback.** Always.

| Dimension | AX Rung (Accessibility) | PX Rung (Pixel Fallback) |
|---|---|---|
| Protocol | AT-SPI2 D-Bus (org.a11y.Bus) | `ydotool` via /dev/uinput |
| Background Safe | 100% — no focus, no promotion | Best-effort; may need surface visibility |
| Focus Required | No | Yes, for some operations |
| Speed | Fast (D-Bus attribute query) | Slow (vision model inference) |
| Token Cost | Low | High |

## 3. Capture (Screenshot)

AX Rung does not support capture. Use PX Rung for screenshots.

```bash
# Preferred: org.gnome.Shell.Screenshot D-Bus (GNOME 42+)
gdbus call --session \
  --dest org.gnome.Shell \
  --object-path /org/gnome/Shell/Screenshot \
  --method org.gnome.Shell.Screenshot.Screenshot \
  "false" "false" "false" \
  | grep -oP "'[^']*'" | head -1 | tr -d "'"
```

```bash
# Fallback: gnome-screenshot CLI
gnome-screenshot --file /tmp/screen.png 2>/dev/null && base64 /tmp/screen.png
```

## 4. Text Entry

Use AX Rung. Does not steal focus.

```bash
# 1. Find the application's accessible object
APP_PID=$(pgrep -x <target-app> | head -1)
REGISTRY=$(gdbus call --session \
  --dest org.a11y.Bus \
  --object-path /org/a11y/bus \
  --method org.a11y.Bus.GetRegistry)

# 2. Accessible applications expose org.a11y.atspi.Text
#    Call insertText via the application's D-Bus accessible object
gdbus call --session \
  --dest org.a11y.atspi.Accessible \
  --object-path /org/a11y/atspi/accessible/<id> \
  --method org.a11y.atspi.Text.InsertText \
  <cursor_position> "<text>"
```

If AT-SPI2 is unavailable, fall back to ydotool:

```bash
ydotool type "<text>"
```

## 5. Clicks

Use AX Rung. Does not steal focus.

```bash
# 1. Enumerate accessible applications
# 2. Find the target element by PID + role
# 3. Invoke the action
gdbus call --session \
  --dest org.a11y.atspi.Accessible \
  --object-path /org/a11y/atspi/accessible/<id> \
  --method org.a11y.atspi.Action.DoAction \
  0
```

PX Rung fallback (coordinates required):

```bash
ydotool mousemove --absolute --xpos <x> --ypos <y>
ydotool click 1  # left click
```

## 6. Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| org.a11y.Bus D-Bus error | Bus not started | `systemctl --user start at-spi-bus-launcher.service` |
| org.gnome.Shell.Screenshot refuses | GNOME < 42 | `gnome-screenshot --file /tmp/s.png` |
| ydotool does nothing | User not in input group | `sudo usermod -aG input $USER` then re-login |
| 0x0 capture | No screenshot source | Use `gnome-screenshot` fallback |
| X11Error 8 | XWayland blocks root grabs | Use D-Bus screenshot path |

## 7. Agent Integration

This skill auto-loads in Hermes from `~/.hermes/skills/gnome-wayland-computer-use/SKILL.md`.

| Other Agent | Method |
|---|---|
| **Claude Code** | `.claude/settings.json`: `{"skills": ["path/to/SKILL.md"]}` |
| **Cursor** | `@SKILL.md` in `.cursorrules` |
| **Aider** | `.aider.conf.yml`: `--read SKILL.md` |
| **Generic** | `cat SKILL.md` into system prompt |
