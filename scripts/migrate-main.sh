#!/usr/bin/env bash
# migrate-main.sh — retire artifacts installed by the public pre-2.3 GWCU main line.
set -euo pipefail

NAME="gnome-wayland-computer-use"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/$NAME"
PRIMARY="$HOME/.agents/skills/$NAME"
MODE=repair
COMPAT=false
QUIET=false
UDEV_RULE="${GWCU_UDEV_RULE_PATH:-/etc/udev/rules.d/80-gnome-wayland-computer-use.rules}"
LEGACY_RULE_VALUE='KERNEL=="uinput", GROUP="input", MODE="0660", TAG+="uaccess", OPTIONS+="static_node=uinput"'
OLD_SERVICE="$HOME/.config/systemd/user/gnome-wayland-computer-use.service"
OLD_YDO="$HOME/.config/systemd/user/ydotoold.service"
OLD_EXTENSION_UUID="desktop-capture@gnome-wayland-computer-use"
OLD_EXTENSION="$HOME/.local/share/gnome-shell/extensions/$OLD_EXTENSION_UUID"
OLD_HERMES_SKILL="$HERMES_HOME/skills/$NAME"
SOUL="$HERMES_HOME/SOUL.md"
SOUL_START='<!-- gnome-wayland-computer-use:start -->'
SOUL_END='<!-- gnome-wayland-computer-use:end -->'
SOUL_CREATED="$HERMES_HOME/backups/$NAME/soul-created-by-installer"

usage(){
  cat <<'HELP'
Usage: migrate-main.sh [--repair|--verify|--detect] [--compat] [--quiet]

Repairs installations made by the published pre-2.3 `main` installer without
removing user-owned state. Exact legacy GWCU services, uinput rule, desktop
capture extension and SOUL routing block are retired. Unproven package/group
ownership is preserved.
HELP
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repair) MODE=repair ;;
    --verify) MODE=verify ;;
    --detect) MODE=detect ;;
    --compat) COMPAT=true ;;
    --quiet) QUIET=true ;;
    --state) shift; [ $# -gt 0 ] || { printf 'error: --state needs a path\n' >&2; exit 2; }; STATE="$1" ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'error: unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

info(){ $QUIET || printf '[INFO] %s\n' "$*"; }
ok(){ $QUIET || printf '[OK] %s\n' "$*"; }
warn(){ printf '[WARN] %s\n' "$*" >&2; }
as_root(){
  if [ "$EUID" -eq 0 ]; then "$@"
  elif command -v pkexec >/dev/null 2>&1; then pkexec "$@"
  elif command -v sudo >/dev/null 2>&1; then sudo "$@"
  else return 126
  fi
}

legacy_version(){
  local f v
  for f in "$PRIMARY/VERSION" "$HERMES_HOME/skills/computer-use/VERSION" "$OLD_HERMES_SKILL/VERSION"; do
    [ -f "$f" ] || continue
    IFS= read -r v <"$f" || true
    case "$v" in 0.*|1.*|2.0.*|2.1.*|2.2.*) printf '%s\n' "$v"; return 0;; esac
  done
  return 1
}

old_service_owned(){
  [ -f "$OLD_SERVICE" ] &&
    grep -Fq 'Description=cua-driver backend for GNOME Wayland computer use' "$OLD_SERVICE" &&
    grep -Fq '/gnome-wayland-computer-use/scripts/serve.sh' "$OLD_SERVICE"
}
old_ydo_owned(){
  [ -f "$OLD_YDO" ] &&
    grep -Fq 'Description=ydotool uinput daemon' "$OLD_YDO" &&
    grep -Fq 'ExecStart=/usr/bin/env ydotoold' "$OLD_YDO"
}
old_extension_owned(){
  [ -f "$OLD_EXTENSION/metadata.json" ] &&
    grep -Eq '"uuid"[[:space:]]*:[[:space:]]*"desktop-capture@gnome-wayland-computer-use"' "$OLD_EXTENSION/metadata.json"
}
old_soul_owned(){ [ -f "$SOUL" ] && grep -Fxq "$SOUL_START" "$SOUL"; }
old_hermes_skill_owned(){ [ -d "$OLD_HERMES_SKILL" ] && [ -f "$OLD_HERMES_SKILL/.gnome-wayland-computer-use-managed" ]; }
old_rule_owned(){ [ -f "$UDEV_RULE" ] && grep -Fxq "$LEGACY_RULE_VALUE" "$UDEV_RULE"; }

legacy_detected(){
  legacy_version >/dev/null 2>&1 || old_service_owned || old_ydo_owned || old_extension_owned || old_soul_owned || old_hermes_skill_owned || old_rule_owned
}

remove_soul_block(){
  local clean
  old_soul_owned || return 0
  clean=$(mktemp)
  awk -v s="$SOUL_START" -v e="$SOUL_END" '$0==s{m=1;next}$0==e{m=0;next}!m{print}' "$SOUL" >"$clean"
  if [ -f "$SOUL_CREATED" ] && ! grep -q '[^[:space:]]' "$clean"; then
    rm -f "$clean" "$SOUL" "$SOUL_CREATED"
  else
    chmod --reference="$SOUL" "$clean" 2>/dev/null || chmod 600 "$clean"
    mv "$clean" "$SOUL"
    rm -f "$SOUL_CREATED"
  fi
}

verify_clean(){
  local failed=0
  old_service_owned && { warn "legacy GWCU cua service remains: $OLD_SERVICE"; failed=1; }
  old_ydo_owned && { warn "legacy GWCU ydotool service remains: $OLD_YDO"; failed=1; }
  old_extension_owned && { warn "legacy GWCU desktop-capture extension remains: $OLD_EXTENSION"; failed=1; }
  old_soul_owned && { warn "legacy GWCU SOUL routing remains in $SOUL"; failed=1; }
  old_hermes_skill_owned && { warn "legacy Hermes skill alias remains: $OLD_HERMES_SKILL"; failed=1; }
  if old_rule_owned; then
    if $COMPAT; then warn "compat mode: legacy GWCU uinput rule still needs removal: $UDEV_RULE"
    else warn "legacy GWCU uinput rule remains: $UDEV_RULE"; failed=1
    fi
  fi
  [ "$failed" -eq 0 ]
}

case "$MODE" in
  detect)
    legacy_detected
    ;;
  verify)
    verify_clean
    ;;
  repair)
    if ! legacy_detected; then
      $QUIET || ok "No published-main migration needed"
      exit 0
    fi

    version=$(legacy_version 2>/dev/null || printf 'pre-2.3')
    info "Repairing published GWCU main installation (${version})"
    mkdir -p "$STATE"; chmod 700 "$STATE" 2>/dev/null || true

    if [ -f "$OLD_SERVICE" ]; then
      if old_service_owned; then
        systemctl --user disable --now gnome-wayland-computer-use.service >/dev/null 2>&1 || true
        rm -f "$OLD_SERVICE"
        ok "Retired old GWCU cua-driver user service"
      elif legacy_version >/dev/null 2>&1; then
        warn "Project-named service exists but does not match the published GWCU service; preserving it: $OLD_SERVICE"
      fi
    fi

    if [ -f "$OLD_YDO" ]; then
      if old_ydo_owned; then
        systemctl --user disable --now ydotoold.service >/dev/null 2>&1 || true
        rm -f "$OLD_YDO"
        ok "Retired old GWCU ydotool daemon"
      fi
    fi

    if old_extension_owned; then
      command -v gnome-extensions >/dev/null 2>&1 && gnome-extensions disable "$OLD_EXTENSION_UUID" >/dev/null 2>&1 || true
      rm -rf "$OLD_EXTENSION"
      ok "Retired old GWCU desktop-capture extension"
    fi

    if old_soul_owned; then
      remove_soul_block
      ok "Removed old always-loaded Hermes SOUL routing"
    fi

    if old_hermes_skill_owned; then
      rm -rf "$OLD_HERMES_SKILL"
      ok "Removed old Hermes skill alias"
    fi

    if old_rule_owned; then
      if $COMPAT; then
        warn "compat mode: obsolete GWCU uinput rule will remain until a live repair: $UDEV_RULE"
      elif as_root rm -f "$UDEV_RULE"; then
        as_root udevadm control --reload-rules >/dev/null 2>&1 || true
        ok "Removed old GWCU uinput rule"
      else
        warn "Could not remove old GWCU uinput rule: $UDEV_RULE"
      fi
    fi

    systemctl --user daemon-reload >/dev/null 2>&1 || true

    # `main` 2.2 could install ydotool and add the user to the input group, but
    # it recorded no ownership for either. Do not guess and remove unrelated
    # host configuration; make the residual explicit instead.
    if id -nG "${USER:-$(id -un)}" 2>/dev/null | tr ' ' '\n' | grep -Fxq input; then
      warn "Legacy main used the 'input' group but did not record whether it added this membership; preserving it to avoid breaking unrelated tools."
    fi

    verify_clean || { warn "Published-main repair is incomplete"; exit 1; }
    printf '%s\n' "$version" >"$STATE/repaired-main-version"
    chmod 600 "$STATE/repaired-main-version" 2>/dev/null || true
    ok "Published-main installation repaired"
    ;;
esac
