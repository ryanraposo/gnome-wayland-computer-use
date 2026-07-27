---
name: gnome-wayland-computer-use
description: Enable GNOME Wayland computer_use.
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [gnome, wayland, cua, computer-use, linux-desktop]
    category: devops
    requires_toolsets: [terminal]
---

# gnome-wayland-computer-use

Diagnoses the GNOME Wayland capture stack, auto-fixes every failure mode,
then calls `computer_use(action="capture", mode="som")`. Auto-restarts
GNOME Shell if needed (no logout required).

For general GUI automation use `cua-driver-rs` instead.

## 1. Quick environment check

```bash
SESSION=$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Type 2>/dev/null | cut -d= -f2)
DESKTOP=$(loginctl show-session "$(loginctl list-sessions --no-legend | awk '{print $1}')" -p Desktop 2>/dev/null | cut -d= -f2)
echo "session_type=$SESSION"
echo "desktop=$DESKTOP"
echo "has_gnome_shell=$(pgrep -x gnome-shell >/dev/null && echo yes || echo no)"
echo "has_xwayland=$(pgrep -x Xwayland >/dev/null && echo yes || echo no)"
echo "has_cua_driver=$(command -v cua-driver >/dev/null && echo yes || echo no)"
if command -v cua-driver &>/dev/null; then
  echo "cua_version=$(cua-driver --version 2>&1 | grep -oP '\d+\.\d+\.\d+' | head -1)"
fi
echo "has_extension_files=$(test -f "${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/winrects@cua/extension.js" && echo yes || echo no)"
if command -v gnome-extensions &>/dev/null; then
  echo "ext_state=$(gnome-extensions info winrects@cua 2>/dev/null | grep -i state | tr -d ' \t')"
fi
echo "has_hermes_systemd=$(systemctl --user --type service list-units --all 2>/dev/null | grep -q hermes-webui.service && echo yes || echo no)"
PID=$(pgrep -x cua-driver | head -1)
if [ -n "$PID" ]; then
  for v in WAYLAND_DISPLAY XDG_SESSION_TYPE CUA_DRIVER_RS_ENABLE_WAYLAND; do
    val=$(tr '\0' '\n' < "/proc/$PID/environ" 2>/dev/null | grep "^${v}=" || echo "$v=<unset>")
    echo "driver_$val"
  done
fi
```

- **Not Wayland / not GNOME?** → Jump to step 6.
- **All green?** → Jump to step 5, then step 6.
- **Missing anything?** → Continue.

## 2. Install / update cua-driver

If `has_cua_driver=no` or version < 0.12.6:

```bash
curl -fsSL https://cua.ai/driver/install.sh | bash
```

## 3. Install & enable winrects@cua

If `has_extension_files=no` or `ext_state` not `State:ACTIVE`:

```bash
UUID="winrects@cua"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
mkdir -p "$DEST"
curl -fsSL -o "$DEST/metadata.json" \
  "https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/metadata.json"
curl -fsSL -o "$DEST/extension.js" \
  "https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/extension.js"

if command -v gnome-extensions &>/dev/null; then
  gnome-extensions enable "$UUID"
  sleep 1
  STATE=$(gnome-extensions info "$UUID" 2>/dev/null | grep -i state | tr -d ' \t')
  if [ "$STATE" = "State:ACTIVE" ]; then
    echo "EXTENSION_ACTIVE"
  else
    echo "NEEDS_RESTART"
  fi
else
  cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")
  python3 - "$cur" "$UUID" << 'PY'
import ast, subprocess, sys
try:    l = ast.literal_eval(sys.argv[1])
except: l = []
if sys.argv[2] not in l: l.append(sys.argv[2])
subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(l)])
PY
  echo "NEEDS_RESTART"
fi
```

If `NEEDS_RESTART`, log out and back in.

## 4. Fix Hermes systemd env vars

If `has_hermes_systemd=yes` and `driver_WAYLAND_DISPLAY` or `driver_CUA_DRIVER_RS_ENABLE_WAYLAND` is `<unset>`:

```bash
mkdir -p ~/.config/systemd/user/hermes-webui.service.d
cat > ~/.config/systemd/user/hermes-webui.service.d/wayland-env.conf << 'EOF'
[Service]
Environment=XDG_SESSION_TYPE=wayland
Environment=XDG_CURRENT_DESKTOP=ubuntu:GNOME
Environment=WAYLAND_DISPLAY=wayland-0
Environment=DISPLAY=:0
Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1
EOF
systemctl --user daemon-reload
systemctl --user restart hermes-webui.service
sleep 3
```

## 5. Verify D-Bus capture

```bash
rects=$(gdbus call --session --dest org.cua.WinRects --object-path /org/cua/WinRects --method org.cua.WinRects.GetRects 2>&1)
png=$(gdbus call --session --dest org.cua.WinRects --object-path /org/cua/WinRects --method org.cua.WinRects.Capture 2>&1)
echo "rects_ok=$([ -n "$rects" ] && echo yes || echo no)"
echo "png_ok=$([ -n "$png" ] && echo yes || echo no)"
```

If either fails → extension not loaded. Run step 3's restart block and retry.

## 6. Run computer_use

Call `computer_use(action="capture", mode="som")` and return the result.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| D-Bus works but `computer_use` returns 0x0 | cua-driver not using winrects@cua path | Set `CUA_DRIVER_RS_ENABLE_WAYLAND=1` on cua-driver process. Restart Hermes. |
| `gnome-extensions info` shows ACTIVE but D-Bus fails | Shell screenshot API unavailable | GNOME ≥ 42? Check `journalctl -f`. |
| cua-driver < 0.12.6 | Old binary without Wayland shell-helper | `cua-driver update --apply` or reinstall. |
| "No WAYLAND_DISPLAY" but `loginctl` says Wayland | systemd strips env vars | Create drop-in (step 4), restart Hermes. |
| wayland_backend ❌ foreign-toplevel=false | GNOME doesn't use wlroots | Expected. Ignore. |
| Ubuntu 26.04: WAYLAND_DISPLAY unset | GNOME doesn't export var | Hardcode `WAYLAND_DISPLAY=wayland-0` in drop-in. |
