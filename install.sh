#!/usr/bin/env bash
# install.sh — install GWCU + WORLDLINE around Cua Driver on Ubuntu GNOME Wayland.
set -euo pipefail

NAME="gnome-wayland-computer-use"
VERSION="2.3.0"
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
CUA_DRIVER_RS_VERSION="${GWCU_CUA_DRIVER_RS_VERSION:-0.19.3}" # deliberately pinned
SELF=""; [ -f "${BASH_SOURCE[0]:-}" ] && SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
as_root(){ if command -v pkexec >/dev/null; then pkexec "$@"; elif command -v sudo >/dev/null; then sudo "$@"; else die "pkexec or sudo is required"; fi; }
get_file(){ local r=$1 d=$2; mkdir -p "$(dirname "$d")"; if [ -n "$SELF" ] && [ -f "$SELF/$r" ]; then cp "$SELF/$r" "$d"; else curl -fsSL --retry 3 --retry-delay 1 -o "$d" "$BASE_URL/$r" || die "download failed: $r"; fi; }
portal_has(){ gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop 2>/dev/null | grep -q "interface org.freedesktop.portal.$1"; }
resolve_cua(){ command -v cua-driver 2>/dev/null || { [ -x "$HOME/.local/bin/cua-driver" ] && printf '%s\n' "$HOME/.local/bin/cua-driver"; }; }
ensure_managed_path(){
  export PATH="$HOME/.local/bin:$PATH"
  local files=("$HOME/.profile"); case "${SHELL##*/}" in bash) files+=("$HOME/.bashrc");; zsh) files+=("$HOME/.zshrc");; esac
  for f in "${files[@]}"; do mkdir -p "$(dirname "$f")"; touch "$f"; grep -Fq '# >>> gnome-wayland-computer-use PATH >>>' "$f" && continue; cat >>"$f" <<'PATH'

# >>> gnome-wayland-computer-use PATH >>>
case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac
# <<< gnome-wayland-computer-use PATH <<<
PATH
  done
}

COMPAT=false; EXPLICIT_UNATTENDED=false; HERMES_MODE=auto
for arg in "$@"; do case "$arg" in
  --compat) COMPAT=true;; --unattended) EXPLICIT_UNATTENDED=true;;
  --hermes) HERMES_MODE=require;; --agent-only) HERMES_MODE=skip;;
  --help|-h)
    cat <<'HELP'
Usage: install.sh [--compat] [--unattended] [--hermes|--agent-only]
  --compat       install files without requiring a live GNOME Wayland session
  --unattended   accept defaults; privilege/portal UI can still appear
  --hermes       require Hermes integration
  --agent-only   skip Hermes integration

Environment:
  GWCU_CUA_DRIVER_RS_VERSION=<version>  deliberate Cua pin override
  GWCU_TRUTHS=off                       disable managed .gwcu at runtime
  GWCU_SCOPE_ROOT=<path>                explicit truth scope
HELP
    exit 0;;
  *) die "unknown option: $arg";; esac; done
[ "$EUID" -ne 0 ] || die "Run as the logged-in desktop user, not sudo"
LOGIN_USER="${USER:-$(id -un)}"
HERMES=false; case "$HERMES_MODE" in auto) command -v hermes >/dev/null && HERMES=true || true;; require) command -v hermes >/dev/null || die "Hermes requested but not found"; HERMES=true;; skip) :;; esac
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"; mkdir -p "$STATE"; chmod 700 "$STATE"
PRIMARY="$HOME/.agents/skills/$NAME"

printf '\nCOMPUTER USE // WORLDLINE // INSTALL\n\n'
if ! $COMPAT; then
  [ -r /etc/os-release ] || die "/etc/os-release missing"
  . /etc/os-release
  [ "${ID:-}" = ubuntu ] || die "Supported host: Ubuntu 26.04 GNOME Wayland"
  dpkg --compare-versions "${VERSION_ID:-0}" ge 26.04 || die "Ubuntu 26.04+ required"
  [ "${XDG_SESSION_TYPE:-$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Type --value 2>/dev/null || true)}" = wayland ] || die "Wayland session required"
  printf '%s' "${XDG_CURRENT_DESKTOP:-$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Desktop --value 2>/dev/null || true)}" | grep -qi gnome || die "GNOME session required"
fi

info "[1/8] Qualifying Ubuntu portal/PipeWire/AT-SPI foundation"
PKGS=(ca-certificates curl libglib2.0-bin pipewire pipewire-bin wireplumber xdg-desktop-portal xdg-desktop-portal-gnome python3 python3-dbus python3-gi python3-gst-1.0 gstreamer1.0-tools gstreamer1.0-pipewire gstreamer1.0-plugins-base gstreamer1.0-plugins-good gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0 gir1.2-atspi-2.0 at-spi2-core libei1 libxkbcommon0)
missing=(); for p in "${PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ ${#missing[@]} -gt 0 ]; then $COMPAT && warn "compat mode: packages missing: ${missing[*]}" || { as_root apt-get update; as_root apt-get install -y "${missing[@]}"; }; fi
if ! $COMPAT; then
  pipewire --version 2>/dev/null | awk 'NR==1{print $NF}' | grep -Eq '^[0-9]' || die "PipeWire unavailable"
  PW=$(pipewire --version 2>/dev/null | awk 'NR==1{print $NF}'); dpkg --compare-versions "$PW" ge 0.3.40 || die "PipeWire 0.3.40+ required"
  portal_has RemoteDesktop || die "RemoteDesktop portal unavailable"
  portal_has ScreenCast || die "ScreenCast portal unavailable"
  portal_has Screenshot || die "Screenshot portal unavailable"
  /usr/bin/python3 - <<'PY' || die "Python GI/AT-SPI/GStreamer bindings unavailable"
import gi
for n,v in (("Gio","2.0"),("Gst","1.0"),("GstVideo","1.0"),("GdkPixbuf","2.0"),("Atspi","2.0")): gi.require_version(n,v)
from gi.repository import Gio,Gst,GstVideo,GdkPixbuf,Atspi
PY
fi
ok "Ubuntu native foundation qualified"

info "[2/8] Installing / qualifying pinned Cua Driver $CUA_DRIVER_RS_VERSION"
ensure_managed_path; CUA=$(resolve_cua || true); CUA_INSTALLED_BY_GWCU=false
if [ -n "$CUA" ] && "$CUA" --version 2>/dev/null | grep -Fq "$CUA_DRIVER_RS_VERSION"; then
  ok "Qualified Cua Driver $CUA_DRIVER_RS_VERSION already installed"
else
  [ -z "$CUA" ] && CUA_INSTALLED_BY_GWCU=true
  CUA_DRIVER_RS_VERSION="$CUA_DRIVER_RS_VERSION" CUA_DRIVER_RS_NO_MODIFY_PATH=1 /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)" || die "Cua installer failed"
  CUA=$(resolve_cua || true); [ -n "$CUA" ] || die "cua-driver missing after install"
fi
"$CUA" --version 2>/dev/null | grep -Fq "$CUA_DRIVER_RS_VERSION" || die "Expected Cua $CUA_DRIVER_RS_VERSION"

info "[3/8] Installing Cua GNOME Wayland helper"
CUA_HOME="${CUA_DRIVER_HOME:-$HOME/.cua-driver}"; HELPER="$CUA_HOME/packages/current/wayland-helper"; CUA_HELPER_INSTALLER="$HELPER/install.sh"
[ -x "$CUA_HELPER_INSTALLER" ] || die "Cua packaged helper missing: packages/current/wayland-helper"
"$CUA_HELPER_INSTALLER" || die "Cua GNOME helper installation failed"
RELOAD_REQUIRED=false; gnome-extensions info winrects@cua >/dev/null 2>&1 && gnome-extensions info winrects@cua 2>/dev/null | grep -qi 'State: ACTIVE' || RELOAD_REQUIRED=true

info "[4/8] Installing GWCU runtime, skill and WORLDLINE"
FILES=(VERSION README.md WORLDLINE.md GWCU.md DETERMINISM.md CAPABILITIES.md PERF_NOTES.md references/skill-ux-contract.md scripts/action-span.py scripts/app-identity.sh scripts/capture.sh scripts/check-update.sh scripts/computer-use.sh scripts/cua-health.py scripts/diagnose.sh scripts/observe.sh scripts/observer.py scripts/portal-control.py scripts/profile.sh scripts/teardown.sh scripts/truths.py scripts/worldline.py scripts/worldline-capture.sh systemd/user/gnome-wayland-computer-use-observer.socket systemd/user/gnome-wayland-computer-use-observer.service systemd/user/gnome-wayland-computer-use-worldline.socket systemd/user/gnome-wayland-computer-use-worldline.service)
rm -rf "$TMP/bundle"; mkdir -p "$TMP/bundle"
for f in "${FILES[@]}"; do get_file "$f" "$TMP/bundle/$f"; done
get_file SKILL.md "$TMP/bundle/SKILL.md"
for f in "$TMP/bundle/scripts"/*.sh "$TMP/bundle/scripts"/*.py; do chmod +x "$f"; done
BACKUPS="$HERMES_HOME/backups/$NAME"; MANIFEST="$BACKUPS/manifest.tsv"
install_dir(){
  local src=$1 dst=$2 backup
  if [ -e "$dst" ] && [ ! -f "$dst/.gnome-wayland-computer-use-managed" ]; then
    mkdir -p "$BACKUPS"; backup="$BACKUPS/$(date +%s%N)-$(basename "$dst")"; mv "$dst" "$backup"; printf '%s\t%s\n' "$dst" "$backup" >>"$MANIFEST"
  fi
  rm -rf "$dst"; mkdir -p "$(dirname "$dst")"; cp -a "$src" "$dst"; : >"$dst/.gnome-wayland-computer-use-managed"
}
install_dir "$TMP/bundle" "$PRIMARY"
if $HERMES; then
  HSKILL="$HERMES_HOME/skills/computer-use"; install_dir "$TMP/bundle" "$HSKILL"
  PLUGIN="$HERMES_HOME/plugins/$NAME"; mkdir -p "$TMP/plugin"; get_file runtimes/hermes/plugin.yaml "$TMP/plugin/plugin.yaml"; get_file runtimes/hermes/__init__.py "$TMP/plugin/__init__.py"; install_dir "$TMP/plugin" "$PLUGIN"
  hermes plugins enable "$NAME" >/dev/null 2>&1 || warn "Hermes plugin installed; enable it manually if needed"
fi
ok "Installed action-span.py + WORLDLINE runtime + skill"

info "[5/8] Configuring managed .gwcu preference and RemoteDesktop consent"
PREF="$STATE/managed-truths"; if [ ! -s "$PREF" ]; then value=on; if ! $EXPLICIT_UNATTENDED && [ -r /dev/tty ]; then printf 'Enable managed .gwcu local truths? Git scopes add /.gwcu to .gitignore before storing machine/workspace facts [Y/n]: ' >/dev/tty; read -r reply </dev/tty || reply=""; [[ "$reply" =~ ^[nN] ]] && value=off; fi; printf '%s\n' "$value" >"$PREF"; chmod 600 "$PREF"; fi
[ "${GWCU_TRUTHS:-}" = off ] && warn "GWCU_TRUTHS=off overrides managed truth at runtime"
if ! $COMPAT; then
  set +e; PORTAL_STATUS=$("$PRIMARY/scripts/portal-control.py" --status 2>/dev/null); set -e
  TOKEN=$(python3 - "$PORTAL_STATUS" <<'PY'
import json,sys
try: print("yes" if json.loads(sys.argv[1]).get("portal",{}).get("restore_token",{}).get("present") else "no")
except Exception: print("no")
PY
)
  if [ "$TOKEN" != yes ]; then
    info "GNOME calls this compositor-approved local input permission 'Remote Desktop'. GWCU installs no RDP/VNC server."
    info "The bootstrap sends no click or key; it performs one pointer move through Cua."
    for n in 3 2 1; do printf '\r[INFO] GNOME permission prompt may appear in %s... ' "$n"; sleep 1; done; printf '\n'
    "$PRIMARY/scripts/portal-control.py" --authorize --driver "$CUA" --timeout 90 >"$STATE/portal-control.json" || die "RemoteDesktop authorization failed"
  fi
fi
ok "Local truth preference + control consent prepared"

info "[6/8] Removing stale project control artifacts"
LEGACY="$HOME/.config/systemd/user/gnome-wayland-computer-use.service"; if [ -f "$LEGACY" ]; then systemctl --user disable --now gnome-wayland-computer-use.service 2>/dev/null || true; rm -f "$LEGACY"; fi
# No project-owned raw-input daemon/rule is installed. Exact old artifacts are retired by teardown.
systemctl --user daemon-reload 2>/dev/null || true
ok "Cua remains the only actuator"

info "[7/8] Enabling WORLDLINE + lazy ScreenCast observer"
UNIT_DIR="$HOME/.config/systemd/user"; mkdir -p "$UNIT_DIR"
for u in gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service gnome-wayland-computer-use-worldline.socket gnome-wayland-computer-use-worldline.service; do cp "$PRIMARY/systemd/user/$u" "$UNIT_DIR/$u"; done
systemctl --user daemon-reload || $COMPAT || die "user systemd reload failed"
for u in gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service gnome-wayland-computer-use-worldline.socket gnome-wayland-computer-use-worldline.service; do systemctl --user reset-failed "$u" 2>/dev/null || true; done
if ! $COMPAT; then
  systemctl --user enable --now gnome-wayland-computer-use-observer.socket || die "observer socket failed"
  systemctl --user enable --now gnome-wayland-computer-use-worldline.socket || die "WORLDLINE socket failed"
fi
/usr/bin/python3 "$PRIMARY/scripts/observer.py" self-test >/dev/null || die "observer.py self-test failed"
/usr/bin/python3 "$PRIMARY/scripts/worldline.py" self-test >/dev/null || die "worldline.py self-test failed"
ok "WORLDLINE revision daemon + private ScreenCast observer ready"

info "[8/8] Proving installed-state health"
PREV_ACCESS=$(gsettings get org.gnome.desktop.interface toolkit-accessibility 2>/dev/null || printf unknown); ACCESS_CHANGED=false
if [ "$PREV_ACCESS" = false ]; then gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null && ACCESS_CHANGED=true || true; fi
mkdir -p "$STATE"
python3 - "$STATE/ownership.json" "$PREV_ACCESS" "$ACCESS_CHANGED" "$CUA_INSTALLED_BY_GWCU" "$CUA_DRIVER_RS_VERSION" "$HERMES" <<'PY'
import json,os,pathlib,sys
p=pathlib.Path(sys.argv[1]);d={"schema":"gwcu.ownership.v3","toolkit_accessibility":{"previous":sys.argv[2],"changed":sys.argv[3]=="true"},"upstream":{"cua_driver":{"provisioned":sys.argv[4]=="true","owned":sys.argv[4]=="true","version":sys.argv[5]},"winrects":{"owned":False}},"user_units":{"observer_socket":True,"observer_service":True,"worldline_socket":True,"worldline_service":True},"hermes_plugin":{"managed":sys.argv[6]=="true","name":"gnome-wayland-computer-use"},"distro_foundation_owned":False};p.write_text(json.dumps(d,separators=(",",":"))+"\n");os.chmod(p,0o600)
PY
if ! $COMPAT; then
  DOCTOR_OUT="$STATE/cua-doctor.json"; DOCTOR_ERR="$STATE/cua-doctor.stderr"; rc=0; "$CUA" doctor --json >"$DOCTOR_OUT" 2>"$DOCTOR_ERR" || rc=$?
  doctor_mentions_drm(){ { cat "$1" 2>/dev/null; cat "$2" 2>/dev/null; } | grep -Eiq '(/dev/dri|DRM|render node|video group|permission[^[:cntrl:]]*(card|render|gpu))'; }
  if [ "$rc" -ne 0 ] && doctor_mentions_drm "$DOCTOR_OUT" "$DOCTOR_ERR" && ! id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -qx video; then
    if $EXPLICIT_UNATTENDED || { printf 'Cua reported DRM access trouble. Add %s to video group? [Y/n] ' "$LOGIN_USER" >/dev/tty; read -r x </dev/tty || x=""; [[ ! "$x" =~ ^[nN] ]]; }; then as_root adduser "$LOGIN_USER" video; : >"$STATE/video-group-added"; die "DRM access repaired; sign out/in once, then rerun install.sh"; fi
  fi
  [ "$rc" -eq 0 ] || { cat "$DOCTOR_ERR" >&2 || true; die "cua-driver doctor failed"; }
  "$PRIMARY/scripts/cua-health.py" --driver "$CUA" >"$STATE/cua-health.json" || die "Cua health_report failed"
  /usr/bin/python3 "$PRIMARY/scripts/worldline.py" request --json '{"op":"status"}' >/dev/null || die "WORLDLINE socket not responding"
fi
ok "Installed state healthy"

printf '\n'
if $RELOAD_REQUIRED; then printf 'READY EXCEPT GNOME HELPER RELOAD\nReload/sign out once so GNOME loads winrects@cua.\n'; elif $COMPAT; then printf 'INSTALLED FOR NEXT UBUNTU GNOME SESSION\n'; else printf 'READY. Cua controls; WORLDLINE watches; .gwcu remembers.\n'; fi
