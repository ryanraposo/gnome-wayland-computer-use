---
name: gnome-wayland-computer-use
description: |
  Diagnose Wayland vs X11 and install winrects@cua for GNOME.
version: 1.0.0
platforms: [linux]
category: desktop-automation
---

# Linux Wayland Computer-Use

Diagnose, set up, and troubleshoot `computer_use` on Linux Wayland sessions — GNOME Mutter, wlroots compositors (Sway, hyprland, labwc), or KDE KWin. The diagnostic and fix path differs significantly from X11.

## Detecting Wayland vs X11

`hermes computer-use doctor` only checks `$WAYLAND_DISPLAY` — which may NOT be inherited by the Hermes shell session even on a Wayland desktop. Never trust a "not Wayland" conclusion from the doctor alone.

**To determine the actual display server, check multiple signals:**

```
echo "DISPLAY=$DISPLAY"
echo "XDG_SESSION_TYPE=$XDG_SESSION_TYPE"
loginctl list-sessions --no-legend | while read s rest; do
  loginctl show-session "$s" -p Type -p Display 2>/dev/null
done
ps aux | grep -E "(gdm-wayland|Xwayland|sway|hyprland|kwin_wayland)" | grep -v grep
```

**Signals:**
- `XDG_SESSION_TYPE=wayland` or `loginctl` shows `Type=wayland` → Wayland
- `Xwayland :0` process running → Wayland with XWayland compatibility layer
- `gdm-wayland-session` running → GNOME on Wayland
- `DISPLAY=:0` but no Xorg process → XWayland (Wayland underneath)

## GNOME Wayland — the winrects@cua extension

On **GNOME Mutter Wayland**, `computer_use` captures return **0x0** with no elements even though the doctor shows `✅ ax_capability` and `✅ screen_capture`. This is because GNOME native Wayland clients are invisible to the XWayland AT-SPI bridge. The fix is installing the `winrects@cua` GNOME Shell extension.

### What winrects@cua provides

| Capability | Without extension | With extension |
|---|---|---|
| Window screen coordinates | ❌ | ✅ via D-Bus `org.cua.WinRects` |
| Compositor stage capture | ❌ | ✅ via Shell screenshot API |
| Window activation for input targeting | ❌ | ✅ verified focus |
| Agent cursor rendering | ❌ | ✅ Clutter actor on stage |

### How to install

Download `metadata.json` and `extension.js` from the cua-driver repo and install:

```bash
UUID="winrects@cua"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
mkdir -p "$DEST"

# Download files
curl -fsSL -o "$DEST/metadata.json" \
  "https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/metadata.json"
curl -fsSL -o "$DEST/extension.js" \
  "https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/extension.js"

# Enable via gsettings (preserves existing extensions)
cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")
python3 - "$cur" "$UUID" <<'PY'
import sys, ast, subprocess
try: l = ast.literal_eval(sys.argv[1])
except: l = []
if sys.argv[2] not in l: l.append(sys.argv[2])
subprocess.run(["gsettings","set","org.gnome.shell","enabled-extensions",str(l)])
PY
```

**After install: log out and back in.** GNOME Shell loads extensions only at session startup. Verify with:

```bash
gnome-extensions info winrects@cua
# → State: ACTIVE
```

cua-driver auto-detects the extension at runtime via `wayland::shell_helper`. No config changes needed.

## Wayland compositor differences

| Compositor | Helper needed? | Notes |
|---|---|---|
| **GNOME Mutter** | `winrects@cua` | Requires the extension for capture, coords, input targeting |
| **wlroots (Sway, hyprland, labwc)** | None | cua-driver uses foreign-toplevel activation, virtual-pointer input, and layer-shell natively |
| **KDE KWin** | Not yet available | Portal reachability alone insufficient; no target-addressable KWin adapter exists yet |

## Doctor tool blind spots

The `hermes computer-use doctor` has these known gaps:

1. **Wayland detection**: Only checks `$WAYLAND_DISPLAY` env var. On GNOME Wayland, this var may not be inherited by the Hermes shell — the doctor says "not Wayland" when it actually is.
2. **Screen capture on Wayland**: On GNOME Wayland without `winrects@cua`, `screen_capture_capability` returns ✅ because it tests the XWayland X11 path, but the XWayland surface has no windows to capture.
3. **ax_capability**: Can also return ✅ for X11/XWayland even when real windows are invisible.

Always independently verify with `loginctl`, process inspection, and `XDG_SESSION_TYPE` before concluding the display server type based on doctor output alone.

## Verification after setup

```python
# Check extension is active
result = terminal("gnome-extensions info winrects@cua")
# Expect "State: ACTIVE"

# Try a capture
# computer_use(action="capture", mode="som")
# Should return >0 elements with non-zero dimensions
```
