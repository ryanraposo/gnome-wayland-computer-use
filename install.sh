#!/usr/bin/env bash
# install.sh — install GWCU + WORLDLINE around Cua Driver on Ubuntu GNOME Wayland.
set -euo pipefail

NAME="gnome-wayland-computer-use"
VERSION="2.3.0"
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
CUA_DRIVER_RS_VERSION="${GWCU_CUA_DRIVER_RS_VERSION:-0.19.3}" # deliberately pinned
PYTHON="${GWCU_SYSTEM_PYTHON:-/usr/bin/python3}"
SELF=""; [ -f "${BASH_SOURCE[0]:-}" ] && SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

info(){ printf '\033[34m[INFO]\033[0m %s\n' "$*"; }
ok(){ printf '\033[32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[33m[WARN]\033[0m %s\n' "$*"; }
die(){ printf '\033[31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }
as_root(){ if command -v pkexec >/dev/null; then pkexec "$@"; elif command -v sudo >/dev/null; then sudo "$@"; else die "pkexec or sudo is required"; fi; }
get_file(){ local r=$1 d=$2; mkdir -p "$(dirname "$d")"; if [ -n "$SELF" ] && [ -f "$SELF/$r" ]; then cp "$SELF/$r" "$d"; else curl -fsSL --retry 3 --retry-delay 1 -o "$d" "$BASE_URL/$r" || die "download failed: $r"; fi; }
# worldline_request: prove the WORLDLINE socket serves status. The unit can be
# left with a stale pathname (active but file missing) and the first
# socket-activated request races service startup, so re-arm the socket and retry.
worldline_request(){
  local i rdir sock
  rdir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/$NAME"
  sock="$rdir/worldline.sock"
  for i in 1 2 3 4 5 6 7 8; do
    if [ -S "$sock" ] && "$PYTHON" "$PRIMARY/scripts/worldline.py" request --json '{"op":"status"}' >/dev/null 2>&1; then return 0; fi
    if [ -S "$sock" ]; then sleep 1; continue; fi
    systemctl --user stop gnome-wayland-computer-use-worldline.service >/dev/null 2>&1 || true
    systemctl --user stop gnome-wayland-computer-use-worldline.socket >/dev/null 2>&1 || true
    systemctl --user reset-failed gnome-wayland-computer-use-worldline.service gnome-wayland-computer-use-worldline.socket >/dev/null 2>&1 || true
    systemctl --user start gnome-wayland-computer-use-worldline.socket >/dev/null 2>&1 || true
    sleep 1
  done
  return 1
}
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
write_cua_ownership(){
  local provisioned="$1" version="$2" existing="$STATE/ownership.json" tmp
  tmp=$(mktemp "$STATE/.ownership.XXXXXX")
  "$PYTHON" - "$existing" "$tmp" "$provisioned" "$version" <<'PY'
import json,os,pathlib,sys
src,out,prov,version=sys.argv[1:]
try: d=json.load(open(src))
except Exception: d={}
d.setdefault("schema","gwcu.ownership.v3")
u=d.setdefault("upstream",{}); c=u.setdefault("cua_driver",{})
old=bool(c.get("provisioned") or c.get("owned"))
c.update({"provisioned": old or prov=="true", "owned": old or prov=="true", "version":version})
p=pathlib.Path(out);p.write_text(json.dumps(d,separators=(",",":"))+"\n");os.chmod(p,0o600)
PY
  mv -f "$tmp" "$existing"
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
  GWCU_BACKGROUND_PRIORITY=on|off       prefer background computer use at runtime
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
PKGS=(ca-certificates curl git libglib2.0-bin pipewire pipewire-bin wireplumber xdg-desktop-portal xdg-desktop-portal-gnome python3 python3-dbus python3-gi python3-gst-1.0 gstreamer1.0-tools gstreamer1.0-pipewire gstreamer1.0-plugins-base gstreamer1.0-plugins-good gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0 gir1.2-atspi-2.0 at-spi2-core libei1 libxkbcommon0)
missing=(); for p in "${PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ ${#missing[@]} -gt 0 ]; then $COMPAT && warn "compat mode: packages missing: ${missing[*]}" || { as_root apt-get update; as_root apt-get install -y "${missing[@]}"; }; fi
if ! $COMPAT; then
  PW=$(pipewire --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$PW" ] || die "PipeWire unavailable"
  dpkg --compare-versions "$PW" ge 0.3.40 || die "PipeWire 0.3.40+ required"
  portal_has RemoteDesktop || die "RemoteDesktop portal unavailable"
  portal_has ScreenCast || die "ScreenCast portal unavailable"
  portal_has Screenshot || die "Screenshot portal unavailable"
  "$PYTHON" - <<'PY' || die "Python GI/AT-SPI/GStreamer bindings unavailable"
import gi
for n,v in (("Gio","2.0"),("Gst","1.0"),("GstVideo","1.0"),("GdkPixbuf","2.0"),("Atspi","2.0")): gi.require_version(n,v)
from gi.repository import Gio,Gst,GstVideo,GdkPixbuf,Atspi
PY
fi
ok "Ubuntu native foundation qualified"

# Public main <=2.2 installed its own Cua service, ydotool/uinput plane,
# desktop-capture extension and Hermes routing. Retire those before touching the
# new Cua/portal path so two generations never run concurrently during upgrade.
MIGRATOR="$TMP/migrate-main.sh"
get_file scripts/migrate-main.sh "$MIGRATOR"; chmod +x "$MIGRATOR"
migration_args=(--repair --state "$STATE")
$COMPAT && migration_args+=(--compat)
"$MIGRATOR" "${migration_args[@]}" || die "Could not repair an older published GWCU installation"

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
# Persist upstream ownership immediately. Reinstalls OR the existing value, so a
# later failure or rerun cannot forget that GWCU originally provisioned Cua.
write_cua_ownership "$CUA_INSTALLED_BY_GWCU" "$CUA_DRIVER_RS_VERSION"

info "[3/8] Installing Cua GNOME Wayland helper"
CUA_HOME="${CUA_DRIVER_HOME:-$HOME/.cua-driver}"; HELPER="$CUA_HOME/packages/current/wayland-helper"; CUA_HELPER_INSTALLER="$HELPER/install.sh"
[ -x "$CUA_HELPER_INSTALLER" ] || die "Cua packaged helper missing: packages/current/wayland-helper/install.sh"
"$CUA_HELPER_INSTALLER" || die "Cua GNOME helper installation failed"
# Enable the WinRects extension so GNOME loads it immediately
gnome-extensions enable winrects@cua 2>/dev/null || true
RELOAD_REQUIRED=false; gnome-extensions info winrects@cua >/dev/null 2>&1 && gnome-extensions info winrects@cua 2>/dev/null | grep -qi 'State: ACTIVE' || RELOAD_REQUIRED=true

info "[4/8] Installing GWCU runtime, skill and WORLDLINE"
FILES=(VERSION README.md agents/openai.yaml scripts/action-span.py scripts/app-identity.sh scripts/capture.sh scripts/check-update.sh scripts/computer-use.sh scripts/cua-health.py scripts/diagnose.sh scripts/mcp_client.py scripts/migrate-main.sh scripts/observe.sh scripts/observer.py scripts/portal-control.py scripts/profile.sh scripts/teardown.sh scripts/truths.py scripts/worldline.py scripts/worldline-capture.sh systemd/user/gnome-wayland-computer-use-observer.socket systemd/user/gnome-wayland-computer-use-observer.service systemd/user/gnome-wayland-computer-use-worldline.socket systemd/user/gnome-wayland-computer-use-worldline.service)
rm -rf "$TMP/bundle"; mkdir -p "$TMP/bundle"
for f in "${FILES[@]}"; do get_file "$f" "$TMP/bundle/$f"; done
get_file SKILL.md "$TMP/bundle/SKILL.md"
for f in "$TMP/bundle/scripts"/*.sh "$TMP/bundle/scripts"/*.py; do chmod +x "$f"; done
BACKUPS="$HERMES_HOME/backups/$NAME"; MANIFEST="$BACKUPS/manifest.tsv"
plugin_name_of(){ awk -F': *' '/^name:[[:space:]]*/{gsub(/^[[:space:]]+|[[:space:]]+$|["'\'']/,"",$2); print $2; exit}' "$1"; }
manifest_backup(){
  local dst=$1 backup
  mkdir -p "$BACKUPS"; backup="$BACKUPS/$(date +%s%N)-$(basename "$dst")"; mv "$dst" "$backup"; printf '%s\t%s\n' "$dst" "$backup" >>"$MANIFEST"
}
install_dir(){
  local src=$1 dst=$2
  if [ -e "$dst" ] && [ ! -f "$dst/.gnome-wayland-computer-use-managed" ]; then
    manifest_backup "$dst"
  fi
  rm -rf "$dst"; mkdir -p "$(dirname "$dst")"; cp -a "$src" "$dst"; : >"$dst/.gnome-wayland-computer-use-managed"
}
# A stale Hermes plugin copy (same plugin.yaml name, different directory) still
# registers /computer-use and can shadow the freshly installed one depending on
# plugin scan order. Retire only what GWCU provably owns; archive the rest so
# teardown can restore it.
retire_duplicate_plugins(){
  local canonical=$1 dir name yaml
  [ -d "$HERMES_HOME/plugins" ] || return 0
  for yaml in "$HERMES_HOME/plugins"/*/plugin.yaml; do
    [ -f "$yaml" ] || continue
    name=$(plugin_name_of "$yaml"); [ "$name" = "$NAME" ] || continue
    dir=$(dirname "$yaml"); [ "$dir" != "$canonical" ] || continue
    if [ -f "$dir/.gnome-wayland-computer-use-managed" ]; then
      rm -rf "$dir"; ok "Retired stale duplicate Hermes plugin ${dir/$HOME/\~}"
    else
      warn "Archiving unmanaged duplicate Hermes plugin ${dir/$HOME/\~}; restored on uninstall"
      manifest_backup "$dir"
    fi
  done
}
install_dir "$TMP/bundle" "$PRIMARY"
if $HERMES; then
  HSKILL="$HERMES_HOME/skills/computer-use"
  # The installed skill MUST be the GWCU skill or /computer-use does not work.
  if [ -e "$HSKILL" ] && [ ! -f "$HSKILL/.gnome-wayland-computer-use-managed" ]; then
    warn "Replacing existing computer-use skill at ${HSKILL/$HOME/\~}; it is archived and restored by teardown"
  fi
  install_dir "$TMP/bundle" "$HSKILL"
  PLUGIN="$HERMES_HOME/plugins/$NAME"; mkdir -p "$TMP/plugin"; get_file runtimes/hermes/plugin.yaml "$TMP/plugin/plugin.yaml"; get_file runtimes/hermes/__init__.py "$TMP/plugin/__init__.py"; install_dir "$TMP/plugin" "$PLUGIN"
  retire_duplicate_plugins "$PLUGIN"
  hermes plugins enable "$NAME" >/dev/null 2>&1 || warn "Hermes plugin installed; enable it manually if needed"
fi
ok "Installed action-span.py + WORLDLINE runtime + skill"

info "[5/8] Configuring preferences and RemoteDesktop consent"
PREF="$STATE/managed-truths"; if [ ! -s "$PREF" ]; then value=on; if ! $EXPLICIT_UNATTENDED && [ -r /dev/tty ]; then printf 'Enable managed .gwcu local truths? Git scopes add /.gwcu to .gitignore before storing machine/workspace facts [Y/n]: ' >/dev/tty; read -r reply </dev/tty || reply=""; [[ "$reply" =~ ^[nN] ]] && value=off; fi; printf '%s\n' "$value" >"$PREF"; chmod 600 "$PREF"; fi
[ "${GWCU_TRUTHS:-}" = off ] && warn "GWCU_TRUTHS=off overrides managed truth at runtime"
BACKGROUND_PREF="$STATE/background-priority"
if [ ! -s "$BACKGROUND_PREF" ]; then
  background=off
  if ! $EXPLICIT_UNATTENDED && [ -r /dev/tty ]; then
    printf 'Prioritize background computer use when available? Obvious control is faster and more deterministic [y/N]: ' >/dev/tty
    read -r reply </dev/tty || reply=""
    [[ "$reply" =~ ^[yY] ]] && background=on
  fi
  printf '%s\n' "$background" >"$BACKGROUND_PREF"; chmod 600 "$BACKGROUND_PREF"
fi
case "${GWCU_BACKGROUND_PRIORITY:-}" in on|yes|true|1) warn "GWCU_BACKGROUND_PRIORITY enables background priority at runtime";; off|no|false|0) warn "GWCU_BACKGROUND_PRIORITY disables background priority at runtime";; esac
if ! $COMPAT; then
  set +e; PORTAL_STATUS=$("$PRIMARY/scripts/portal-control.py" --status 2>/dev/null); set -e
  TOKEN=$("$PYTHON" - "$PORTAL_STATUS" <<'PY'
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
ok "Preferences + control consent prepared"

info "[6/8] Verifying published-main repair and single control plane"
verify_args=(--verify --state "$STATE")
$COMPAT && verify_args+=(--compat)
"$MIGRATOR" "${verify_args[@]}" || die "An older published GWCU control artifact still conflicts with the new runtime"
systemctl --user daemon-reload 2>/dev/null || true
ok "Legacy published-main control plane retired; Cua is the only actuator"

info "[7/8] Enabling WORLDLINE + lazy ScreenCast observer"
UNIT_DIR="$HOME/.config/systemd/user"; mkdir -p "$UNIT_DIR"
for u in gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service gnome-wayland-computer-use-worldline.socket gnome-wayland-computer-use-worldline.service; do cp "$PRIMARY/systemd/user/$u" "$UNIT_DIR/$u"; done
systemctl --user daemon-reload || $COMPAT || die "user systemd reload failed"
for u in gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service gnome-wayland-computer-use-worldline.socket gnome-wayland-computer-use-worldline.service; do systemctl --user reset-failed "$u" 2>/dev/null || true; done
if ! $COMPAT; then
  systemctl --user enable --now gnome-wayland-computer-use-observer.socket || die "observer socket failed"
  systemctl --user enable --now gnome-wayland-computer-use-worldline.socket || die "WORLDLINE socket failed"
fi
"$PYTHON" "$PRIMARY/scripts/observer.py" self-test >/dev/null || die "observer.py self-test failed"
"$PYTHON" "$PRIMARY/scripts/worldline.py" self-test >/dev/null || die "worldline.py self-test failed"
ok "WORLDLINE revision daemon + private ScreenCast observer ready"

info "[8/8] Proving installed-state health"
PREV_ACCESS=$(gsettings get org.gnome.desktop.interface toolkit-accessibility 2>/dev/null || printf unknown); ACCESS_CHANGED=false
if [ "$PREV_ACCESS" = false ]; then gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null && ACCESS_CHANGED=true || true; fi
mkdir -p "$STATE"
# Merge final ownership facts; never reset durable Cua provenance recorded above.
"$PYTHON" - "$STATE/ownership.json" "$PREV_ACCESS" "$ACCESS_CHANGED" "$CUA_DRIVER_RS_VERSION" "$HERMES" "$COMPAT" <<'PY'
import json,os,pathlib,sys
p=pathlib.Path(sys.argv[1])
try:d=json.loads(p.read_text())
except Exception:d={}
d["schema"]="gwcu.ownership.v3"
d["toolkit_accessibility"]={"previous":sys.argv[2],"changed":sys.argv[3]=="true"}
u=d.setdefault("upstream",{}); c=u.setdefault("cua_driver",{}); c["version"]=sys.argv[4]; c["owned"]=bool(c.get("provisioned") or c.get("owned")); u.setdefault("winrects",{"owned":False})
enabled=sys.argv[6]!="true"
d["user_units"]={"observer_socket":enabled,"observer_service":enabled,"worldline_socket":enabled,"worldline_service":enabled}
d["hermes_plugin"]={"managed":sys.argv[5]=="true","name":"gnome-wayland-computer-use"};d["distro_foundation_owned"]=False
p.write_text(json.dumps(d,separators=(",",":"))+"\n");os.chmod(p,0o600)
PY
if ! $COMPAT; then
  DOCTOR_OUT="$STATE/cua-doctor.json"; DOCTOR_ERR="$STATE/cua-doctor.stderr"; rc=0; "$CUA" doctor --json >"$DOCTOR_OUT" 2>"$DOCTOR_ERR" || rc=$?
  doctor_mentions_drm(){ { cat "$1" 2>/dev/null; cat "$2" 2>/dev/null; } | grep -Eiq '(/dev/dri|DRM|render node|video group|permission[^[:cntrl:]]*(card|render|gpu))'; }
  if [ "$rc" -ne 0 ] && doctor_mentions_drm "$DOCTOR_OUT" "$DOCTOR_ERR" && ! id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -qx video; then
    if $EXPLICIT_UNATTENDED || { printf 'Cua reported DRM access trouble. Add %s to video group? [Y/n] ' "$LOGIN_USER" >/dev/tty; read -r x </dev/tty || x=""; [[ ! "$x" =~ ^[nN] ]]; }; then as_root adduser "$LOGIN_USER" video; : >"$STATE/video-group-added"; die "DRM access repaired; sign out/in once, then rerun install.sh"; fi
  fi
  [ "$rc" -eq 0 ] || { cat "$DOCTOR_ERR" >&2 || true; die "cua-driver doctor failed"; }
  "$PRIMARY/scripts/cua-health.py" --driver "$CUA" >"$STATE/cua-health.json" || die "Cua health_report failed"
  worldline_request || die "WORLDLINE socket not responding"
fi
ok "Installed state healthy"

printf '\n'
if $RELOAD_REQUIRED; then printf 'READY EXCEPT GNOME HELPER RELOAD\nReload/sign out once so GNOME loads winrects@cua.\n'; elif $COMPAT; then printf 'INSTALLED FOR NEXT UBUNTU GNOME SESSION\n'; else printf 'READY. Cua controls; WORLDLINE watches; .gwcu remembers.\n'; fi
printf '\nUninstall: curl -fsSL %s/uninstall.sh | bash\n' "$BASE_URL"
printf 'Teardown:  %s/scripts/teardown.sh --help\n' "$PRIMARY"
printf '           Cua preserved by default; --remove-cua removes only GWCU-provisioned Cua\n'