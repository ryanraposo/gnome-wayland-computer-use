#!/usr/bin/env bash
# install.sh — install and prove GWCU + WORLDLINE around Cua Driver on Ubuntu GNOME Wayland.
set -euo pipefail

APP_ID="gnome-wayland-computer-use"
VERSION="2.3.0"
BASE_URL="${GWCU_BASE_URL:-https://ryanraposo.github.io/gnome-wayland-computer-use}"
CUA_DRIVER_RS_VERSION="${GWCU_CUA_DRIVER_RS_VERSION:-0.20.0}" # deliberately pinned
PYTHON="${GWCU_SYSTEM_PYTHON:-/usr/bin/python3}"
SELF=""; [ -f "${BASH_SOURCE[0]:-}" ] && SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BLUE=$'\033[34m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
else
  BLUE=""; GREEN=""; YELLOW=""; RED=""; BOLD=""; DIM=""; RESET=""
fi
info(){ printf '%s[INFO]%s %s\n' "$BLUE" "$RESET" "$*"; }
ok(){ printf '%s[OK]%s %s\n' "$GREEN" "$RESET" "$*"; }
warn(){ printf '%s[WARN]%s %s\n' "$YELLOW" "$RESET" "$*"; }
error(){ printf '%s[ERROR]%s %s\n' "$RED" "$RESET" "$*" >&2; }
action(){ printf '%s[ACTION]%s %s\n' "$YELLOW" "$RESET" "$*"; }
die(){ error "$*"; [ -n "${INSTALL_LOG:-}" ] && printf '        details: %s\n' "$INSTALL_LOG" >&2; exit 1; }
needs_session(){ action "$*"; [ -n "${INSTALL_LOG:-}" ] && printf '         details: %s\n' "$INSTALL_LOG"; exit 20; }
as_root(){ if command -v pkexec >/dev/null; then pkexec "$@"; elif command -v sudo >/dev/null; then sudo "$@"; else die "pkexec or sudo is required"; fi; }
get_file(){ local r=$1 d=$2; mkdir -p "$(dirname "$d")"; if [ -n "$SELF" ] && [ -f "$SELF/$r" ]; then cp "$SELF/$r" "$d"; else curl -fsSL --retry 3 --retry-delay 1 -o "$d" "$BASE_URL/$r" || die "download failed: $r"; fi; }
portal_has(){ gdbus introspect --session --dest org.freedesktop.portal.Desktop --object-path /org/freedesktop/portal/desktop 2>/dev/null | grep -q "interface org.freedesktop.portal.$1"; }
resolve_cua(){ command -v cua-driver 2>/dev/null || { [ -x "$HOME/.local/bin/cua-driver" ] && printf '%s\n' "$HOME/.local/bin/cua-driver"; }; }

COMPAT=false
EXPLICIT_UNATTENDED=false
HERMES_MODE=auto
HERMES_ALL_PROFILES=false
HERMES_PROFILE_NAMES=()
while [ $# -gt 0 ]; do
  case "$1" in
    --compat) COMPAT=true ;;
    --unattended) EXPLICIT_UNATTENDED=true ;;
    --hermes) HERMES_MODE=require ;;
    --agent-only) HERMES_MODE=skip ;;
    --hermes-all-profiles) HERMES_ALL_PROFILES=true ;;
    --hermes-profile)
      [ $# -ge 2 ] || die "--hermes-profile requires a profile name"
      HERMES_PROFILE_NAMES+=("$2"); shift ;;
    --hermes-profile=*) HERMES_PROFILE_NAMES+=("${1#*=}") ;;
    --help|-h)
      cat <<'HELP'
Usage: install.sh [--compat] [--unattended] [--hermes|--agent-only]
                  [--hermes-profile NAME ...] [--hermes-all-profiles]
  --compat                install files without requiring a live GNOME Wayland session
  --unattended            accept GWCU defaults without preference prompts
  --hermes                require Hermes integration
  --agent-only            skip Hermes integration
  --hermes-profile NAME   also integrate one existing Hermes profile; repeatable
  --hermes-all-profiles   also integrate every existing Hermes profile

Hermes integration replaces the targeted profile's `computer-use` skill with
GWCU's skill and enables GWCU's policy plugin. It does not replace Hermes'
built-in `computer_use` tool/toolset; the plugin wraps that tool while enabled.
Existing non-GWCU `computer-use` skills are archived for teardown restoration.

Environment:
  GWCU_CUA_DRIVER_RS_VERSION=<version>  deliberate Cua pin override
  GWCU_TRUTHS=off                       disable managed .gwcu at runtime
  GWCU_SCOPE_ROOT=<path>                explicit truth scope
  GWCU_BACKGROUND_PRIORITY=on|off       prefer background computer use at runtime
  GWCU_SYSTEM_PYTHON=<absolute path>    Python used by installed runtime checks
  HERMES_HOME=<path>                    explicit default Hermes home to integrate
  NO_COLOR=1                            disable ANSI installer color
HELP
      exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
  shift
done

if [ "$HERMES_MODE" = skip ] && { $HERMES_ALL_PROFILES || [ ${#HERMES_PROFILE_NAMES[@]} -gt 0 ]; }; then
  die "Hermes profile options cannot be combined with --agent-only"
fi
if $HERMES_ALL_PROFILES || [ ${#HERMES_PROFILE_NAMES[@]} -gt 0 ]; then
  [ "$HERMES_MODE" = auto ] && HERMES_MODE=require
fi

[ "$EUID" -ne 0 ] || die "Run as the logged-in desktop user, not sudo"
[ -x "$PYTHON" ] || die "Configured Python is not executable: $PYTHON"
LOGIN_USER="${USER:-$(id -un)}"
HERMES=false; HERMES_BIN=""
case "$HERMES_MODE" in
  auto) HERMES_BIN=$(command -v hermes 2>/dev/null || true); [ -n "$HERMES_BIN" ] && HERMES=true || true ;;
  require) HERMES_BIN=$(command -v hermes 2>/dev/null || true); [ -n "$HERMES_BIN" ] || die "Hermes requested but not found"; HERMES=true ;;
  skip) : ;;
esac
HERMES_DEFAULT_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_PROFILE_ROOT="${GWCU_HERMES_ROOT:-$HOME/.hermes}"
HERMES_ACTIVE_HOME="$HERMES_DEFAULT_HOME"
HERMES_TARGET_HOMES=()
HERMES_TARGET_COUNT=0
add_hermes_target(){
  local target=$1 existing
  [ -n "$target" ] || return 0
  for existing in "${HERMES_TARGET_HOMES[@]:-}"; do [ "$existing" = "$target" ] && return 0; done
  HERMES_TARGET_HOMES+=("$target")
}
validate_profile_name(){
  case "$1" in ''|.|..|*/*) die "invalid Hermes profile name: $1" ;; esac
}
if $HERMES; then
  add_hermes_target "$HERMES_DEFAULT_HOME"
  if $HERMES_ALL_PROFILES; then
    for d in "$HERMES_PROFILE_ROOT/profiles"/*; do [ -d "$d" ] && add_hermes_target "$d"; done
  fi
  for profile in "${HERMES_PROFILE_NAMES[@]:-}"; do
    validate_profile_name "$profile"
    target="$HERMES_PROFILE_ROOT/profiles/$profile"
    [ -d "$target" ] || die "Hermes profile does not exist: $profile"
    add_hermes_target "$target"
  done
fi

STATE="${XDG_STATE_HOME:-$HOME/.local/state}/$APP_ID"; mkdir -p "$STATE"; chmod 700 "$STATE"
PRIMARY="$HOME/.agents/skills/$APP_ID"
INSTALL_LOG="$STATE/install.log"; touch "$INSTALL_LOG"; chmod 600 "$INSTALL_LOG"
printf '\n=== %s version=%s pid=%s ===\n' "$(date -Is 2>/dev/null || date)" "$VERSION" "$$" >>"$INSTALL_LOG"
log(){ printf '%s\n' "$*" >>"$INSTALL_LOG"; }
run_logged(){ local label=$1; shift; log ">>> $label"; "$@" >>"$INSTALL_LOG" 2>&1; }

read_os_release(){
  (
    set +u
    . /etc/os-release
    printf '%s\n%s\n' "${ID:-}" "${VERSION_ID:-}"
  )
}

ensure_managed_path(){
  export PATH="$HOME/.local/bin:$PATH"
  local files=("$HOME/.profile"); case "${SHELL##*/}" in bash) files+=("$HOME/.bashrc");; zsh) files+=("$HOME/.zshrc");; esac
  local f
  for f in "${files[@]}"; do
    mkdir -p "$(dirname "$f")"; touch "$f"
    grep -Fq '# >>> gnome-wayland-computer-use PATH >>>' "$f" && continue
    cat >>"$f" <<'PATH'

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

probe_daemon(){ local key=$1; shift; "$@" >"$STATE/$key-probe.json" 2>"$STATE/$key-probe.stderr"; }
daemon_failure_capsule(){
  local key=$1 label=$2 socket_unit=$3 service_unit=$4
  {
    printf '\n=== %s LIVE PROOF FAILURE ===\n' "$label"
    systemctl --user show "$socket_unit" "$service_unit" --no-pager -p Id -p LoadState -p ActiveState -p SubState -p Result -p ExecMainCode -p ExecMainStatus -p FragmentPath 2>&1 || true
    printf '%s\n' '--- service journal ---'; journalctl --user -u "$service_unit" -n 40 --no-pager 2>&1 || true
    printf '%s\n' '--- last probe stdout ---'; cat "$STATE/$key-probe.json" 2>/dev/null || true
    printf '%s\n' '--- last probe stderr ---'; cat "$STATE/$key-probe.stderr" 2>/dev/null || true
  } >>"$INSTALL_LOG"
  error "$label failed its live RPC proof after automatic repair"
  printf '        unit: %s\n        log:  %s\n' "$service_unit" "$INSTALL_LOG" >&2
}
ensure_user_daemon(){
  local key=$1 label=$2 socket_unit=$3 service_unit=$4; shift 4
  local -a probe=("$@") delays=(0 .05 .10 .20 .35 .55 .85 1.25); local delay
  if probe_daemon "$key" "${probe[@]}"; then return 0; fi
  warn "$label did not answer the first live probe; repairing its socket/service pair"
  { systemctl --user reset-failed "$service_unit" "$socket_unit" || true; systemctl --user stop "$service_unit" || true; systemctl --user restart "$socket_unit" || true; } >>"$INSTALL_LOG" 2>&1
  for delay in "${delays[@]}"; do [ "$delay" = 0 ] || sleep "$delay"; probe_daemon "$key" "${probe[@]}" && { ok "$label recovered and answered"; return 0; }; done
  run_logged "$label direct service restart" systemctl --user restart "$service_unit" || true
  for delay in .05 .10 .20 .35 .55 .85 1.25; do sleep "$delay"; probe_daemon "$key" "${probe[@]}" && { ok "$label recovered and answered"; return 0; }; done
  daemon_failure_capsule "$key" "$label" "$socket_unit" "$service_unit"; return 1
}

hermes_exec(){ ( cd "$HOME" && HERMES_HOME="$HERMES_ACTIVE_HOME" NO_COLOR=1 "$HERMES_BIN" "$@" ); }
hermes_json_list(){
  local key=$1 out
  out=$(hermes_exec config get "$key" --json 2>>"$INSTALL_LOG" || true)
  "$PYTHON" - "$out" <<'PY'
import json,sys
try:v=json.loads(sys.argv[1])
except Exception:v=[]
print(json.dumps(v if isinstance(v,list) else [],separators=(",",":")))
PY
}
hermes_list_with(){
  local json=$1 item=$2
  "$PYTHON" - "$json" "$item" <<'PY'
import json,sys
try:v=json.loads(sys.argv[1])
except Exception:v=[]
item=sys.argv[2]
out=[]
for x in v if isinstance(v,list) else []:
    if isinstance(x,str) and x not in out:out.append(x)
if item not in out:out.append(item)
print(json.dumps(out,separators=(",",":")))
PY
}
hermes_list_without(){
  local json=$1 item=$2
  "$PYTHON" - "$json" "$item" <<'PY'
import json,sys
try:v=json.loads(sys.argv[1])
except Exception:v=[]
item=sys.argv[2]
print(json.dumps([x for x in v if isinstance(x,str) and x!=item],separators=(",",":")))
PY
}
hermes_plugin_enabled(){
  local out
  out=$(hermes_exec plugins list --plain --no-bundled 2>>"$INSTALL_LOG" || hermes_exec plugins list --plain 2>>"$INSTALL_LOG" || true)
  printf '%s\n' "$out" >>"$INSTALL_LOG"
  printf '%s\n' "$out" | grep -Eq "^enabled[[:space:]].*[[:space:]]${APP_ID}$"
}
HERMES_POLICY_STATUS="not-detected"
configure_hermes(){
  local enabled disabled
  info "Enabling GWCU's Hermes integration in ${HERMES_ACTIVE_HOME/$HOME/\~}"
  enabled=$(hermes_list_with "$(hermes_json_list plugins.enabled)" "$APP_ID")
  disabled=$(hermes_list_without "$(hermes_json_list plugins.disabled)" "$APP_ID")
  run_logged "Hermes enable GWCU [$HERMES_ACTIVE_HOME]" hermes_exec config set plugins.enabled "$enabled" --force || die "Hermes could not persist plugin enablement in $HERMES_ACTIVE_HOME"
  run_logged "Hermes un-disable GWCU [$HERMES_ACTIVE_HOME]" hermes_exec config set plugins.disabled "$disabled" --force || die "Hermes could not clear a stale GWCU disable in $HERMES_ACTIVE_HOME"
  run_logged "Hermes grant GWCU tools.override [$HERMES_ACTIVE_HOME]" hermes_exec config set "plugins.entries.$APP_ID.granted_capabilities" '["tools.override"]' --force || die "Hermes could not grant GWCU tools.override in $HERMES_ACTIVE_HOME"
  run_logged "Hermes bridge GWCU tool override [$HERMES_ACTIVE_HOME]" hermes_exec config set "plugins.entries.$APP_ID.allow_tool_override" true --force || die "Hermes could not persist GWCU tool override gate in $HERMES_ACTIVE_HOME"
  if hermes_plugin_enabled; then
    ok "Hermes plugin enabled; computer_use policy is mechanical (${HERMES_ACTIVE_HOME/$HOME/\~})"
  else
    HERMES_POLICY_STATUS="enable-failed"
    die "Hermes is installed but the exact GWCU plugin could not be enabled in $HERMES_ACTIVE_HOME"
  fi
}

printf '\n%sCOMPUTER USE // WORLDLINE // INSTALL%s\n\n' "$BOLD" "$RESET"
if ! $COMPAT; then
  [ -r /etc/os-release ] || die "/etc/os-release missing"
  mapfile -t OS_RELEASE < <(read_os_release)
  OS_ID="${OS_RELEASE[0]:-}"; OS_VERSION_ID="${OS_RELEASE[1]:-0}"
  [ "$OS_ID" = ubuntu ] || die "Supported host: Ubuntu 26.04 GNOME Wayland"
  dpkg --compare-versions "$OS_VERSION_ID" ge 26.04 || die "Ubuntu 26.04+ required"
  SESSION_TYPE="${XDG_SESSION_TYPE:-$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Type --value 2>/dev/null || true)}"
  SESSION_DESKTOP="${XDG_CURRENT_DESKTOP:-$(loginctl show-session "${XDG_SESSION_ID:-self}" -p Desktop --value 2>/dev/null || true)}"
  [ "$SESSION_TYPE" = wayland ] || die "Wayland session required"
  printf '%s' "$SESSION_DESKTOP" | grep -qi gnome || die "GNOME session required"
fi

info "[1/8] Qualifying Ubuntu portal/PipeWire/AT-SPI foundation"
PKGS=(ca-certificates curl git libglib2.0-bin pipewire pipewire-bin wireplumber xdg-desktop-portal xdg-desktop-portal-gnome python3 python3-dbus python3-gi python3-gst-1.0 gstreamer1.0-tools gstreamer1.0-pipewire gstreamer1.0-plugins-base gstreamer1.0-plugins-good gir1.2-gstreamer-1.0 gir1.2-gst-plugins-base-1.0 gir1.2-gdkpixbuf-2.0 gir1.2-atspi-2.0 at-spi2-core libei1 libxkbcommon0)
missing=(); for p in "${PKGS[@]}"; do dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [ ${#missing[@]} -gt 0 ]; then if $COMPAT; then warn "compat mode: packages missing: ${missing[*]}"; else as_root apt-get update; as_root apt-get install -y "${missing[@]}"; fi; fi
if ! $COMPAT; then
  PW=$(pipewire --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1); [ -n "$PW" ] || die "PipeWire unavailable"
  dpkg --compare-versions "$PW" ge 0.3.40 || die "PipeWire 0.3.40+ required"
  portal_has RemoteDesktop || die "RemoteDesktop portal unavailable"; portal_has ScreenCast || die "ScreenCast portal unavailable"; portal_has Screenshot || die "Screenshot portal unavailable"
  "$PYTHON" - <<'PY' || die "Python GI/AT-SPI/GStreamer bindings unavailable"
import gi
for n,v in (("Gio","2.0"),("Gst","1.0"),("GstVideo","1.0"),("GdkPixbuf","2.0"),("Atspi","2.0")):gi.require_version(n,v)
from gi.repository import Gio,Gst,GstVideo,GdkPixbuf,Atspi
PY
fi
ok "Ubuntu native foundation qualified"

MIGRATOR="$TMP/migrate-main.sh"
get_file scripts/migrate-main.sh "$MIGRATOR"; chmod +x "$MIGRATOR"
migration_args=(--repair --state "$STATE"); $COMPAT && migration_args+=(--compat)
"$MIGRATOR" "${migration_args[@]}" || die "Could not repair an older published GWCU installation"

info "[2/8] Installing / qualifying pinned Cua Driver $CUA_DRIVER_RS_VERSION"
ensure_managed_path; CUA=$(resolve_cua || true); CUA_INSTALLED_BY_GWCU=false
if [ -n "$CUA" ] && "$CUA" --version 2>/dev/null | grep -Fq "$CUA_DRIVER_RS_VERSION"; then ok "Qualified Cua Driver $CUA_DRIVER_RS_VERSION already installed"; else
  [ -z "$CUA" ] && CUA_INSTALLED_BY_GWCU=true
  CUA_DRIVER_RS_VERSION="$CUA_DRIVER_RS_VERSION" CUA_DRIVER_RS_NO_MODIFY_PATH=1 /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)" || die "Cua installer failed"
  CUA=$(resolve_cua || true); [ -n "$CUA" ] || die "cua-driver missing after install"
fi
"$CUA" --version 2>/dev/null | grep -Fq "$CUA_DRIVER_RS_VERSION" || die "Expected Cua $CUA_DRIVER_RS_VERSION"
write_cua_ownership "$CUA_INSTALLED_BY_GWCU" "$CUA_DRIVER_RS_VERSION"

info "[3/8] Installing Cua GNOME Wayland helper"
CUA_HOME="${CUA_DRIVER_HOME:-$HOME/.cua-driver}"; HELPER="$CUA_HOME/packages/current/wayland-helper"; CUA_HELPER_INSTALLER="$HELPER/install.sh"
[ -x "$CUA_HELPER_INSTALLER" ] || die "Cua packaged helper missing: packages/current/wayland-helper/install.sh"
if run_logged "Cua GNOME helper install" "$CUA_HELPER_INSTALLER"; then ok "Cua GNOME helper installed"; else tail -n 20 "$INSTALL_LOG" >&2 || true; die "Cua GNOME helper installation failed"; fi
gnome-extensions enable winrects@cua >>"$INSTALL_LOG" 2>&1 || true
RELOAD_REQUIRED=false
if gnome-extensions info winrects@cua >/dev/null 2>&1 && gnome-extensions info winrects@cua 2>/dev/null | grep -qi 'State: ACTIVE'; then ok "winrects@cua is ACTIVE"; else RELOAD_REQUIRED=true; warn "winrects@cua is installed and will become active after one GNOME sign-out/sign-in"; fi

info "[4/8] Installing GWCU runtime, skill and WORLDLINE"
FILES=(VERSION README.md agents/openai.yaml scripts/action-span.py scripts/app-identity.sh scripts/capture.sh scripts/check-update.sh scripts/computer-use.sh scripts/cua-health.py scripts/diagnose.sh scripts/mcp_client.py scripts/migrate-main.sh scripts/observe.sh scripts/observer.py scripts/portal-control.py scripts/present-window.py scripts/profile.sh scripts/teardown.sh scripts/truths.py scripts/worldline.py scripts/worldline-capture.sh systemd/user/gnome-wayland-computer-use-observer.socket systemd/user/gnome-wayland-computer-use-observer.service systemd/user/gnome-wayland-computer-use-worldline.socket systemd/user/gnome-wayland-computer-use-worldline.service)
rm -rf "$TMP/bundle"; mkdir -p "$TMP/bundle"
for f in "${FILES[@]}"; do get_file "$f" "$TMP/bundle/$f"; done
get_file SKILL.md "$TMP/bundle/SKILL.md"
for f in "$TMP/bundle/scripts"/*.sh "$TMP/bundle/scripts"/*.py; do chmod +x "$f"; done
plugin_name_of(){ awk -F': *' '/^name:[[:space:]]*/{gsub(/^[[:space:]]+|[[:space:]]+$|["'\'']/,"",$2); print $2; exit}' "$1"; }
manifest_backup(){ local dst=$1 backup; mkdir -p "$BACKUPS"; backup="$BACKUPS/$(date +%s%N)-$(basename "$dst")"; mv "$dst" "$backup"; printf '%s\t%s\n' "$dst" "$backup" >>"$MANIFEST"; }
install_dir(){ local src=$1 dst=$2; if [ -e "$dst" ] && [ ! -f "$dst/.gnome-wayland-computer-use-managed" ]; then manifest_backup "$dst"; fi; rm -rf "$dst"; mkdir -p "$(dirname "$dst")"; cp -a "$src" "$dst"; : >"$dst/.gnome-wayland-computer-use-managed"; }
retire_duplicate_plugins(){
  local canonical=$1 dir name yaml; [ -d "$HERMES_ACTIVE_HOME/plugins" ] || return 0
  for yaml in "$HERMES_ACTIVE_HOME/plugins"/*/plugin.yaml; do
    [ -f "$yaml" ] || continue; name=$(plugin_name_of "$yaml"); [ "$name" = "$APP_ID" ] || continue; dir=$(dirname "$yaml"); [ "$dir" != "$canonical" ] || continue
    if [ -f "$dir/.gnome-wayland-computer-use-managed" ]; then rm -rf "$dir"; ok "Retired stale duplicate Hermes plugin ${dir/$HOME/\~}"; else warn "Archiving unmanaged duplicate Hermes plugin ${dir/$HOME/\~}; restored on uninstall"; manifest_backup "$dir"; fi
  done
}
install_hermes_target(){
  local target=$1 HSKILL PLUGIN
  local HERMES_HOME="$target"
  HERMES_ACTIVE_HOME="$HERMES_HOME"
  BACKUPS="$HERMES_ACTIVE_HOME/backups/$APP_ID"
  MANIFEST="$BACKUPS/manifest.tsv"
  mkdir -p "$HERMES_ACTIVE_HOME/skills" "$HERMES_ACTIVE_HOME/plugins"
  HSKILL="$HERMES_ACTIVE_HOME/skills/computer-use"
  if [ -e "$HSKILL" ] && [ ! -f "$HSKILL/.gnome-wayland-computer-use-managed" ]; then
    warn "Replacing existing computer-use skill at ${HSKILL/$HOME/\~}; archived for teardown"
  fi
  install_dir "$TMP/bundle" "$HSKILL"
  PLUGIN="$HERMES_HOME/plugins/$APP_ID"
  install_dir "$TMP/plugin" "$PLUGIN"
  retire_duplicate_plugins "$PLUGIN"
  configure_hermes
  HERMES_TARGET_COUNT=$((HERMES_TARGET_COUNT + 1))
}
BACKUPS="$HERMES_DEFAULT_HOME/backups/$APP_ID"
MANIFEST="$BACKUPS/manifest.tsv"
install_dir "$TMP/bundle" "$PRIMARY"
if $HERMES; then
  rm -rf "$TMP/plugin"; mkdir -p "$TMP/plugin"
  get_file runtimes/hermes/plugin.yaml "$TMP/plugin/plugin.yaml"
  get_file runtimes/hermes/__init__.py "$TMP/plugin/__init__.py"
  for target in "${HERMES_TARGET_HOMES[@]}"; do install_hermes_target "$target"; done
  HERMES_POLICY_STATUS="enabled:$HERMES_TARGET_COUNT"
fi
ok "Installed action-span.py + exact presentation gate + WORLDLINE runtime + skill"

info "[5/8] Configuring preferences and RemoteDesktop consent"
PREF="$STATE/managed-truths"; if [ ! -s "$PREF" ]; then value=on; if ! $EXPLICIT_UNATTENDED && [ -r /dev/tty ]; then printf 'Enable managed .gwcu local truths? Git scopes add /.gwcu to .gitignore before storing machine/workspace facts [Y/n]: ' >/dev/tty; read -r reply </dev/tty || reply=""; [[ "$reply" =~ ^[nN] ]] && value=off; fi; printf '%s\n' "$value" >"$PREF"; chmod 600 "$PREF"; fi
[ "${GWCU_TRUTHS:-}" = off ] && warn "GWCU_TRUTHS=off overrides managed truth at runtime"
BACKGROUND_PREF="$STATE/background-priority"; if [ ! -s "$BACKGROUND_PREF" ]; then background=off; if ! $EXPLICIT_UNATTENDED && [ -r /dev/tty ]; then printf 'Prioritize background computer use when available? Default visible takeover is faster and deterministic [y/N]: ' >/dev/tty; read -r reply </dev/tty || reply=""; [[ "$reply" =~ ^[yY] ]] && background=on; fi; printf '%s\n' "$background" >"$BACKGROUND_PREF"; chmod 600 "$BACKGROUND_PREF"; fi
case "${GWCU_BACKGROUND_PRIORITY:-}" in on|yes|true|1) warn "GWCU_BACKGROUND_PRIORITY enables background priority at runtime";; off|no|false|0) warn "GWCU_BACKGROUND_PRIORITY disables background priority at runtime";; esac
if ! $COMPAT; then
  set +e; PORTAL_STATUS=$("$PRIMARY/scripts/portal-control.py" --status 2>/dev/null); set -e
  TOKEN=$("$PYTHON" - "$PORTAL_STATUS" <<'PY'
import json,sys
try:print("yes" if json.loads(sys.argv[1]).get("portal",{}).get("restore_token",{}).get("present") else "no")
except Exception:print("no")
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
verify_args=(--verify --state "$STATE"); $COMPAT && verify_args+=(--compat)
"$MIGRATOR" "${verify_args[@]}" || die "An older published GWCU control artifact still conflicts with the new runtime"
systemctl --user daemon-reload 2>/dev/null || true
ok "Legacy published-main control plane retired; Cua is the only actuator"

info "[7/8] Enabling and live-proving WORLDLINE + observer + exact presentation"
UNIT_DIR="$HOME/.config/systemd/user"; mkdir -p "$UNIT_DIR"
for u in gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service gnome-wayland-computer-use-worldline.socket gnome-wayland-computer-use-worldline.service; do cp "$PRIMARY/systemd/user/$u" "$UNIT_DIR/$u"; done
systemctl --user daemon-reload || $COMPAT || die "user systemd reload failed"
for u in gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service gnome-wayland-computer-use-worldline.socket gnome-wayland-computer-use-worldline.service; do systemctl --user reset-failed "$u" 2>/dev/null || true; done
if ! $COMPAT; then systemctl --user enable --now gnome-wayland-computer-use-observer.socket >>"$INSTALL_LOG" 2>&1 || die "observer socket failed to enable"; systemctl --user enable --now gnome-wayland-computer-use-worldline.socket >>"$INSTALL_LOG" 2>&1 || die "WORLDLINE socket failed to enable"; fi
"$PYTHON" "$PRIMARY/scripts/observer.py" self-test >>"$INSTALL_LOG" || die "observer.py self-test failed"
"$PYTHON" "$PRIMARY/scripts/worldline.py" self-test >>"$INSTALL_LOG" || die "worldline.py self-test failed"
"$PYTHON" "$PRIMARY/scripts/present-window.py" self-test >>"$INSTALL_LOG" || die "presentation gate self-test failed"
if ! $COMPAT; then
  ensure_user_daemon observer "ScreenCast observer" gnome-wayland-computer-use-observer.socket gnome-wayland-computer-use-observer.service "$PYTHON" "$PRIMARY/scripts/observer.py" client status || die "ScreenCast observer is not responding"
  ensure_user_daemon worldline "WORLDLINE" gnome-wayland-computer-use-worldline.socket gnome-wayland-computer-use-worldline.service "$PYTHON" "$PRIMARY/scripts/worldline.py" request --json '{"op":"status"}' || die "WORLDLINE is not responding"
  if $RELOAD_REQUIRED; then warn "Exact presentation live proof is deferred until GNOME loads winrects@cua"; else "$PYTHON" "$PRIMARY/scripts/present-window.py" status >"$STATE/presentation.json" 2>>"$INSTALL_LOG" || die "Cua GNOME exact-presentation gate unavailable"; fi
fi
ok "WORLDLINE + observer protocols proved; presentation gate qualified"

info "[8/8] Proving the complete installed state"
PREV_ACCESS=$(gsettings get org.gnome.desktop.interface toolkit-accessibility 2>/dev/null || printf unknown); ACCESS_CHANGED=false
if [ "$PREV_ACCESS" = false ]; then gsettings set org.gnome.desktop.interface toolkit-accessibility true 2>/dev/null && ACCESS_CHANGED=true || true; fi
"$PYTHON" - "$STATE/ownership.json" "$PREV_ACCESS" "$ACCESS_CHANGED" "$CUA_DRIVER_RS_VERSION" "$HERMES" "$COMPAT" "$HERMES_TARGET_COUNT" <<'PY'
import json,os,pathlib,sys
p=pathlib.Path(sys.argv[1])
try:d=json.loads(p.read_text())
except Exception:d={}
d["schema"]="gwcu.ownership.v3";d["toolkit_accessibility"]={"previous":sys.argv[2],"changed":sys.argv[3]=="true"}
u=d.setdefault("upstream",{});c=u.setdefault("cua_driver",{});c["version"]=sys.argv[4];c["owned"]=bool(c.get("provisioned") or c.get("owned"));u.setdefault("winrects",{"owned":False})
enabled=sys.argv[6]!="true";d["user_units"]={"observer_socket":enabled,"observer_service":enabled,"worldline_socket":enabled,"worldline_service":enabled};d["hermes_plugin"]={"managed":sys.argv[5]=="true","name":"gnome-wayland-computer-use","profiles":int(sys.argv[7])};d["distro_foundation_owned"]=False
p.write_text(json.dumps(d,separators=(",",":"))+"\n");os.chmod(p,0o600)
PY
DIAG_CODE="compat"
if ! $COMPAT; then
  DOCTOR_OUT="$STATE/cua-doctor.json"; DOCTOR_ERR="$STATE/cua-doctor.stderr"; rc=0; "$CUA" doctor --json >"$DOCTOR_OUT" 2>"$DOCTOR_ERR" || rc=$?
  doctor_mentions_drm(){ { cat "$1" 2>/dev/null; cat "$2" 2>/dev/null; } | grep -Eiq '(/dev/dri|DRM|render node|video group|permission[^[:cntrl:]]*(card|render|gpu))'; }
  if [ "$rc" -ne 0 ] && doctor_mentions_drm "$DOCTOR_OUT" "$DOCTOR_ERR" && ! id -nG "$LOGIN_USER" | tr ' ' '\n' | grep -qx video; then if $EXPLICIT_UNATTENDED || { printf 'Cua reported DRM access trouble. Add %s to video group? [Y/n] ' "$LOGIN_USER" >/dev/tty; read -r x </dev/tty || x=""; [[ ! "$x" =~ ^[nN] ]]; }; then as_root adduser "$LOGIN_USER" video; : >"$STATE/video-group-added"; needs_session "DRM access repaired. Sign out/in once, then rerun install.sh to complete the live proof."; fi; fi
  [ "$rc" -eq 0 ] || { cat "$DOCTOR_ERR" >&2 || true; die "cua-driver doctor failed"; }
  "$PRIMARY/scripts/cua-health.py" --driver "$CUA" >"$STATE/cua-health.json" || die "Cua health_report failed"
  DIAG_OUT="$STATE/diagnose.json"; diag_rc=0; "$PRIMARY/scripts/diagnose.sh" --machine >"$DIAG_OUT" 2>>"$INSTALL_LOG" || diag_rc=$?
  DIAG_CODE=$("$PYTHON" - "$DIAG_OUT" <<'PY'
import json,sys
try:print(json.load(open(sys.argv[1])).get("code","invalid"))
except Exception:print("invalid")
PY
)
  case "$DIAG_CODE" in ready) :;; reload_required) RELOAD_REQUIRED=true;; *) "$PYTHON" - "$DIAG_OUT" <<'PY' >&2 || true
import json,sys
try:
 d=json.load(open(sys.argv[1]));print("Installed-state proof failed:");print("  host:",d.get("host",{}).get("ok"));print("  observation:",d.get("observation",{}).get("status"));print("  presentation:",d.get("presentation",{}).get("status"));print("  WORLDLINE:",d.get("worldline",{}).get("status"));print("  Cua:",d.get("cua",{}).get("status"));print("  next:",(d.get("next") or {}).get("action"))
except Exception:pass
PY
      die "Installed-state diagnosis failed ($DIAG_CODE)";; esac
fi
MANAGED_VALUE=$(cat "$PREF" 2>/dev/null || printf unknown); BACKGROUND_VALUE=$(cat "$BACKGROUND_PREF" 2>/dev/null || printf unknown)
RECEIPT="$STATE/install-receipt.json"
"$PYTHON" - "$RECEIPT" "$VERSION" "$CUA_DRIVER_RS_VERSION" "$DIAG_CODE" "$RELOAD_REQUIRED" "$HERMES" "$HERMES_POLICY_STATUS" "$MANAGED_VALUE" "$BACKGROUND_VALUE" "$HERMES_TARGET_COUNT" <<'PY'
import json,os,pathlib,sys,time
p=pathlib.Path(sys.argv[1]);d={"schema":"gwcu.install-receipt.v1","version":sys.argv[2],"cua_driver":sys.argv[3],"diagnosis":sys.argv[4],"reload_required":sys.argv[5]=="true","hermes_detected":sys.argv[6]=="true","hermes_policy":sys.argv[7],"managed_truths":sys.argv[8],"background_priority":sys.argv[9],"hermes_profiles":int(sys.argv[10]),"installed_at_unix":int(time.time())};p.write_text(json.dumps(d,separators=(",",":"))+"\n");os.chmod(p,0o600)
PY
ok "Installed state proved; receipt written"

printf '\n%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$DIM" "$RESET"
if $RELOAD_REQUIRED; then printf '%sINSTALL COMPLETE // ONE GNOME RELOAD REQUIRED%s\n' "$BOLD" "$RESET"; printf 'Sign out/in once, rerun ./install.sh, and it will prove exact presentation.\n'; elif $COMPAT; then printf '%sINSTALLED FOR NEXT UBUNTU GNOME SESSION%s\n' "$BOLD" "$RESET"; else printf '%sREADY // PROVED%s\n' "$BOLD" "$RESET"; fi
printf '  Cua Driver:      %s\n' "$CUA_DRIVER_RS_VERSION"
printf '  Visible takeover:%s\n' "$([ "$RELOAD_REQUIRED" = true ] && printf ' pending GNOME reload' || { [ "$COMPAT" = true ] && printf ' installed' || printf ' proved'; })"
printf '  WORLDLINE:       %s\n' "$([ "$COMPAT" = true ] && printf installed || printf ready)"
printf '  Observation:     %s\n' "$([ "$COMPAT" = true ] && printf installed || printf ready)"
printf '  .gwcu truths:    %s\n' "$MANAGED_VALUE"; printf '  Background pref: %s\n' "$BACKGROUND_VALUE"
if $HERMES; then printf '  Hermes policy:   enabled in %s profile(s)\n' "$HERMES_TARGET_COUNT"; else printf '  Hermes:          not detected (agent skill still installed)\n'; fi
printf '%s━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━%s\n' "$DIM" "$RESET"
printf '\n/computer-use trace    exact foreground path\n/computer-use doctor   full machine proof\n'
printf '\nUninstall: curl -fsSL %s/uninstall.sh | bash\n' "$BASE_URL"; printf 'Teardown:  %s/scripts/teardown.sh --help\n' "$PRIMARY"; printf 'Receipt:   %s\nLog:       %s\n' "$RECEIPT" "$INSTALL_LOG"
