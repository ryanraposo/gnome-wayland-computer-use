---
name: gnome-wayland-computer-use
description: |
  Call it once or in place of computer_use. Auto-fixes 0x0 captures on
  GNOME Wayland by diagnosing and repairing the full stack.
version: 1.2.0
platforms: [linux]
category: desktop-automation
---

# GNOME Wayland Computer-Use

Call it once or in place of `computer_use`. Diagnoses the end-to-end stack, fixes every known failure mode, then calls `computer_use` and returns the result. If the session restart needed for extension activation can't be done, it tells the user.

## 1. Quick environment check

Run this   it determines whether GNOME Wayland is in use and gathers state in one shot:

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

- **Not Wayland, not GNOME?** → `computer_use` should work natively. Fall through to step 4.
- **GNOME Wayland with all checks green?** → Jump to step 4 (the D-Bus capture test), then step 5 (call `computer_use`).
- **Anything missing?** → Continue below.

## 2. Install winrects@cua (if missing)

If `has_extension_files=no` or `ext_state` is not `State:ACTIVE`:

```bash
UUID="winrects@cua"
DEST="${XDG_DATA_HOME:-$HOME/.local/share}/gnome-shell/extensions/$UUID"
mkdir -p "$DEST"
curl -fsSL -o "$DEST/metadata.json" \
  "https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/metadata.json"
curl -fsSL -o "$DEST/extension.js" \
  "https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/wayland-helper/winrects%40cua/extension.js"
cur=$(gsettings get org.gnome.shell enabled-extensions 2>/dev/null || echo "@as []")
python3 - "$cur" "$UUID" <<'PY'
import ast, subprocess, sys
try:    l = ast.literal_eval(sys.argv[1])
except: l = []
if sys.argv[2] not in l: l.append(sys.argv[2])
subprocess.run(["gsettings","set","org.gnome.shell","enabled-extensions",str(l)])
PY
echo "INSTALLED"
```

If this step ran, tell the user: *"Extension installed. Log out then back in for it to take effect, then run computer_use."* and stop   the extension can't activate without a session restart.

## 3. Fix Hermes systemd env vars (if applicable)

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

If `driver_CUA_DRIVER_RS_ENABLE_WAYLAND` was missing but the other vars were present, you can skip the restart   just add the missing env var to the existing drop-in instead.

## 4. Verify D-Bus capture works

Probe `winrects@cua` directly (bypasses Hermes/cua-driver path):

```bash
rects=$(gdbus call --session --dest org.cua.WinRects --object-path /org/cua/WinRects --method org.cua.WinRects.GetRects 2>&1)
png=$(gdbus call --session --dest org.cua.WinRects --object-path /org/cua/WinRects --method org.cua.WinRects.Capture 2>&1)
echo "rects_ok=$([ -n "$rects" ] && echo yes || echo no)"
echo "png_ok=$([ -n "$png" ] && echo yes || echo no)"
echo "rects_preview=${rects:0:200}"
```

- If `rects_ok=no` or `png_ok=no` → Extension isn't loaded by GNOME Shell. User needs to log out/in. Tell them and stop.
- If both are yes → The D-Bus capture path is healthy. The only remaining issue is cua-driver's ability to find and use it.

## 5. Run computer_use

Everything is fixed or already working. Call `computer_use(action="capture", mode="som")` and return the result directly.

---

## Reference: troubleshooting matrix

Use this when the above automated flow doesn't resolve the issue (e.g. `computer_use` still returns 0x0 after all steps pass).

| Symptom | Likely cause | Manual fix |
|---|---|---|
| D-Bus `GetRects` returns windows, `Capture` returns PNG, but `computer_use` returns 0x0 | cua-driver not using the winrects@cua path (falling back to XWayland) | Check `CUA_DRIVER_RS_ENABLE_WAYLAND=1` is set on the cua-driver process. Restart Hermes after fixing. |
| `gnome-extensions info` shows `State: ACTIVE` but D-Bus `GetRects` returns nothing | Extension loaded but Shell screenshot API unavailable | Verify GNOME version ≥ 42. Check `journalctl -f` during a capture call for Shell errors. |
| cua-driver version < 0.12.6 | Old binary lacks Wayland shell-helper support | `cua-driver update --apply` or reinstall: `curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/cua-driver/install.sh | bash` |
| cua-driver doctor says "No WAYLAND_DISPLAY" but `loginctl` says Wayland | systemd unit strips env vars | Create the drop-in from step 3, restart Hermes |
| cua-driver doctor shows ❌ wayland_backend (foreign-toplevel=false, etc.) | GNOME Mutter doesn't use wlroots protocols | This is expected. Ignore it   winrects@cua provides the same capabilities via D-Bus. |
| Chrome / native Wayland apps don't appear in element tree | Chrome uses `--ozone-platform=wayland` | Expected. They're captured by winrects@cua in "som" mode but aren't AT-SPI elements. |
| `loginctl` shows `Type=unspecified` | systemd-logind session tracking artifact | Still Wayland if gnome-shell + Xwayland are running. |
| Ubuntu 26.04: `WAYLAND_DISPLAY` unset everywhere | GNOME uses default socket, doesn't export var | Hardcode `WAYLAND_DISPLAY=wayland-0` in the drop-in (step 3 does this). |
