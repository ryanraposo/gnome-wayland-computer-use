---
name: computer-use
description: Drive Ubuntu GNOME and capture its full Wayland desktop.
version: 2.1.0
platforms: [linux]
metadata:
  hermes:
    tags: [computer-use, desktop, automation, gui, gnome, wayland]
    category: desktop
    requires_toolsets: [computer_use, terminal]
---

# Computer Use on Ubuntu GNOME Wayland

Use Hermes's `computer_use` tool for application windows. The installed helper
distinguishes the underlying desktop from the currently visible screen.

## Desktop, Wallpaper, or Desktop Icons

Requests such as "take a screenshot of my desktop", "capture my wallpaper", or
"show my desktop icons" must use this path immediately:

```bash
"$HOME/.hermes/skills/computer-use/scripts/capture.sh" --media
```

The helper creates a timestamped file and prints the exact
`MEDIA:/absolute/path.png` line so Hermes attaches the image. Preserve that
line in the response. Do not analyze or describe the image unless the user
asks, and do not print it as base64.

The primary compositor path captures the wallpaper/icons desktop layer while
verifying that focus, workspace, and window state remain unchanged. Its
compatibility path briefly invokes Show Desktop, takes one full-screen image,
restores Show Desktop, and verifies the compositor window list afterward.

## Visible Screen

Requests such as "capture my screen", "take a screenshot of this display", or
"capture what I am looking at" use:

```bash
"$HOME/.hermes/skills/computer-use/scripts/capture.sh" --media --screen
```

This captures the current visible display, including windows. Do not use
`--screen` for a desktop/wallpaper request.

For a desktop or visible-screen request:

- Do not call `computer_use(action="capture", app="screen")`.
- Do not call `gnome-screenshot`, `grim`, `slurp`, ImageMagick `import`, or
  `org.gnome.Shell.Screenshot` directly.
- Do not probe for alternative screenshot programs.
- If `computer_use` says it captures one window at a time, run the helper
  above immediately.

## Application Windows

For a specific application, capture first:

```text
computer_use(action="capture", mode="som", app="<target app>")
```

Then act using stable element indices:

```text
computer_use(action="click", element=<index>, capture_after=true)
computer_use(action="type", text="<text>", capture_after=true)
```

Prefer element indices over coordinates. Re-capture after state-changing
actions. Keep `raise_window=false` unless the user explicitly asks to bring an
application forward.

## Escalation

Read the structured action result. If it recommends `foreground`, ask before
using a focus-stealing path unless the user's request already requires bringing
the target forward. Raw ydotool input is the final recovery option:

```bash
ydotool type "<text>"
ydotool mousemove --absolute --xpos <x> --ypos <y>
ydotool click 1
```

## Diagnostics

If the helper or backend fails, run:

```bash
"$HOME/.hermes/skills/computer-use/scripts/diagnose.sh"
```

Do not improvise another capture stack before reading the diagnostic result.
