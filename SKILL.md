---
name: gnome-wayland-computer-use
description: Make Hermes computer_use reliable on Ubuntu GNOME Wayland with AT-SPI accessibility, focus-free desktop-layer capture, and verified fallbacks.
version: 1.0.0
platforms: [linux]
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
    category: desktop
    requires_toolsets: [computer_use]
---

# GNOME Wayland Computer-Use Agent Skill

Non-disruptive, background desktop automation on GNOME Wayland under a strict **No-Foreground Contract**: never steal focus, never promote windows, never interrupt the user.

## 1. Hermes Dispatch

When Hermes exposes the `computer_use` tool, use it. It provides screenshots,
stable element indices, accessibility-tree actions, and guarded pixel fallback:

```text
computer_use(action="capture", mode="som", app="<target app>")
computer_use(action="click", element=<index>, capture_after=true)
computer_use(action="type", text="<text>", capture_after=true)
```

Capture before acting and recapture after every state-changing action. Prefer
element indices over coordinates. Keep `raise_window=false` unless the user
explicitly asks to foreground an app.

The shell helpers below are recovery tools for diagnosing the Linux host. Do
not replace a working Hermes `computer_use` action with raw shell input.

## 2. Pre-flight Check

```bash
"$HOME/.hermes/skills/computer-use/scripts/diagnose.sh"
```

## 3. Dual-Rung Dispatch

**AX Rung first. PX Rung fallback.** Always.

| Dimension | AX Rung (Accessibility) | PX Rung (Pixel Fallback) |
|---|---|---|
| Protocol | AT-SPI2 D-Bus (org.a11y.Bus) | `ydotool` via /dev/uinput |
| Background Safe | Focus-free for supported accessible actions | Best-effort; may need surface visibility |
| Focus Required | No | Yes, for some operations |
| Speed | Fast (D-Bus attribute query) | Slow (vision model inference) |
| Token Cost | Low | High |

## 4. Capture (Screenshot)

AX Rung does not support capture. Use PX Rung for screenshots.

The helper distinguishes the underlying desktop from the visible screen and
writes atomically (a failed capture leaves existing output untouched):

```bash
CAPTURE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/capture.sh"
"$CAPTURE" --desktop /tmp/desktop.png
"$CAPTURE" --screen /tmp/screen.png
```

Desktop capture:

1. **GNOME Shell desktop layer** — Temporarily makes normal window actors
   transparent only inside the compositor capture operation. It does not
   minimize, activate, move, resize, or switch workspace. The extension rejects
   success unless focus, workspace, and window state match before and after.
2. **Verified compatibility path** — Invokes Show Desktop, captures with
   Shift+Print, restores Show Desktop, then compares compositor window state.

Visible-screen capture:

1. **`gnome-screenshot --file`** — Used only when already installed on GNOME < 49.
   Registers the allowlisted bus name `org.gnome.Screenshot`.
2. **Screenshot portal** — Requests a non-interactive whole-screen image from
   `org.freedesktop.portal.Screenshot`; no screen-sharing chooser or stream.
3. **`ydotool` fake Shift+Print** — Invokes GNOME's direct full-screen shortcut
   via `/dev/uinput`. GNOME saves the screenshot; we read it from
   `~/Pictures/Screenshots/` and clean up. It may flash briefly but does not
   reuse the interactive screenshot UI's window/selection mode.

The ScreenCast/PipeWire implementation remains available for screen-capture
diagnostics with
`GNOME_WAYLAND_ENABLE_SCREENCAST_FALLBACK=1`, but is not in the default chain
because it may open a screen-sharing chooser.

If all fail, check the troubleshooting table below.

**On GNOME 49+**: `gnome-screenshot` returns `ACCESS_DENIED` (it was removed from
the allowlist). Install the `allow-gnome-screenshot` GNOME Shell extension to
restore it, or rely on the Screenshot portal (preferred — no chooser).

## 5. Text Entry

Use Hermes's AX-backed action. It prefers AT-SPI EditableText and verifies the
result when the target exposes readable text:

```text
computer_use(action="type", text="<text>", capture_after=true)
```

Only when the Hermes tool reports that its backend is unavailable, and the
user has already selected the intended field, use the foreground fallback:

```bash
ydotool type "<text>"
```

## 6. Clicks

Capture and click the returned element index. Hermes routes actionable elements
through AT-SPI `DoAction`, which does not require pixel coordinates:

```text
computer_use(action="capture", mode="som", app="<target app>")
computer_use(action="click", element=<index>, capture_after=true)
```

If the element is absent and the action result recommends foreground
escalation, follow that structured recommendation. Raw ydotool coordinates are
the last recovery option and can affect the user's active desktop:

```bash
ydotool mousemove --absolute --xpos <x> --ypos <y>
ydotool click 1  # left click
```

## 7. Failure Modes

| Symptom | Cause | Fix |
|---|---|---|
| org.a11y.Bus D-Bus error | Bus not started | `systemctl --user start at-spi-bus-launcher.service` |
| `gnome-screenshot` ACCESS_DENIED | GNOME 49+ removed it from allowlist | Use portal fallback or install `allow-gnome-screenshot` extension |
| Portal consent loop | No restore token (GNOME < 46) | Accept once per session; upgrade to GNOME 46+ |
| ydotool does nothing | User not in input group | `sudo usermod -aG input $USER`, then sign out of the GNOME session and sign back in once |
| All capture methods fail | Missing dependencies | Re-run the project installer, then run its diagnostic |
| X11Error 8 | XWayland blocks root grabs | Use the Screenshot portal path |
| `computer_use` backend unavailable | cua-driver service stopped | `systemctl --user restart gnome-wayland-computer-use.service` |

## 8. Agent Integration

Hermes discovers this skill in `~/.hermes/skills/` and loads it on demand when
the task matches its description. Follow any installer request to sign out of
the GNOME session and sign back in once, then start a new Hermes session.

| Other Agent | Method |
|---|---|
| **Claude Code** | `.claude/settings.json`: `{"skills": ["path/to/SKILL.md"]}` |
| **Cursor** | `@SKILL.md` in `.cursorrules` |
| **Aider** | `.aider.conf.yml`: `--read SKILL.md` |
| **Generic** | `cat SKILL.md` into system prompt |
