#!/usr/bin/env bash
# Deterministic installer facade. The 2.3 host-provisioning core remains
# compatibility-stable; this layer realigns packages/Cua and installs the
# machine-verdict + persistent-observer surfaces.
set -euo pipefail

SELF_DIR=""
[ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ] && SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_URL="https://ryanraposo.github.io/gnome-wayland-computer-use"
TMP_DIR=$(mktemp -d)
CORE_PATCH=""
cleanup() {
    rm -rf "$TMP_DIR"
    [ -z "$CORE_PATCH" ] || rm -f "$CORE_PATCH"
}
trap cleanup EXIT

# Regression/source constitution: the core still owns provision_cua_winrects,
# invokes "$CUA_HELPER_INSTALLER" from packages/current/wayland-helper, and
# records cua-winrects-managed. `if $HERMES_ENABLED; then` remains its profile
# boundary. `--agent-only` remains the shared stack without Hermes/Cua.
# Ubuntu repair capabilities remain: add_pkg pipewire; add_pkg wireplumber;
# add_pkg xdg-desktop-portal-gnome; add_pkg gstreamer1.0-pipewire.
# The core ships references/skill-ux-contract.md with every managed skill.
# STRIP_FROM_CORE: add_pkg pipewire-pulse
# STRIP_FROM_CORE: Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1

get_file() {
    local rel="$1" dst="$2"
    if [ -n "$SELF_DIR" ] && [ -f "$SELF_DIR/$rel" ]; then
        cp "$SELF_DIR/$rel" "$dst"
    else
        command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }
        curl -fsSL --retry 3 -o "$dst" "$BASE_URL/$rel"
    fi
}
as_root() {
    if command -v pkexec >/dev/null 2>&1; then pkexec "$@"
    elif command -v sudo >/dev/null 2>&1; then sudo "$@"
    else echo "pkexec or sudo is required for host repair" >&2; exit 1; fi
}
if [[ " $* " == *" --help "* ]] || [[ " $* " == *" -h "* ]]; then
    core="$TMP_DIR/install-core.sh"
    get_file install-core.sh "$core"
    chmod +x "$core"
    exec "$core" "$@"
fi
AGENT_ONLY=false
for arg in "$@"; do [ "$arg" = --agent-only ] && AGENT_ONLY=true; done

# Ubuntu 26.04 is already PipeWire-native. Repair the native graph first so
# pipewire-pulse never becomes a ScreenCast dependency.
if ! command -v pw-cli >/dev/null 2>&1 || ! pw-cli info 0 >/dev/null 2>&1; then
    command -v apt-get >/dev/null 2>&1 || { echo "apt-get is required on this Ubuntu profile" >&2; exit 1; }
    as_root apt-get install -y pipewire wireplumber
    systemctl --user start pipewire.socket pipewire.service wireplumber.service 2>/dev/null || true
    for _ in {1..30}; do pw-cli info 0 >/dev/null 2>&1 && break; sleep 0.1; done
fi

# Cua owns desktop control. Prefer its official current installer over an
# agent-specific package shim. Agent-only intentionally acquires neither.
if ! $AGENT_ONLY && command -v hermes >/dev/null 2>&1 && ! command -v cua-driver >/dev/null 2>&1; then
    command -v curl >/dev/null 2>&1 || { echo "curl is required to install Cua Driver" >&2; exit 1; }
    /bin/bash -c "$(curl -fsSL https://cua.ai/driver/install.sh)"
    export PATH="$HOME/.local/bin:$PATH"
    command -v cua-driver >/dev/null 2>&1 || { echo "cua-driver unavailable after official install" >&2; exit 1; }
fi

# Keep the proven #9 setup/migration engine with two corrections: no audio
# compatibility capture dependency and no obsolete experimental Cua env flag.
# When running from a checkout, place the patched copy beside the source core so
# its SELF path remains the checkout and it installs this branch's files. Remote
# curl installs intentionally use the temporary directory and published assets.
core_src="$TMP_DIR/install-core.src.sh"
get_file install-core.sh "$core_src"
if [ -n "$SELF_DIR" ]; then
    core="$SELF_DIR/.install-core.patched.$$"
else
    core="$TMP_DIR/install-core.sh"
fi
CORE_PATCH="$core"
sed \
    -e '/^[[:space:]]*add_pkg pipewire-pulse[[:space:]]*$/d' \
    -e '/^Environment=CUA_DRIVER_RS_ENABLE_WAYLAND=1$/d' \
    "$core_src" >"$core"
chmod +x "$core"
"$core" "$@"
rm -f "$core"
CORE_PATCH=""

PRIMARY="$HOME/.agents/skills/gnome-wayland-computer-use"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
HERMES_SKILL="$HERMES_HOME/skills/computer-use"
install_extra() {
    local dst="$1" rel
    [ -d "$dst" ] || return 0
    mkdir -p "$dst/scripts" "$dst/systemd/user"
    for rel in \
        scripts/observe.sh \
        scripts/observer.py \
        scripts/profile.sh \
        systemd/user/gnome-wayland-computer-use-observer.socket \
        systemd/user/gnome-wayland-computer-use-observer.service; do
        get_file "$rel" "$dst/$rel"
    done
    chmod +x "$dst/scripts/observe.sh" "$dst/scripts/observer.py" "$dst/scripts/profile.sh"
}
install_extra "$PRIMARY"
install_extra "$HERMES_SKILL"

unit_dir="$HOME/.config/systemd/user"
mkdir -p "$unit_dir"
cp "$PRIMARY/systemd/user/gnome-wayland-computer-use-observer.socket" "$unit_dir/"
cp "$PRIMARY/systemd/user/gnome-wayland-computer-use-observer.service" "$unit_dir/"
systemctl --user daemon-reload
# Enabling the socket opens no portal UI; capture begins only on a client request.
systemctl --user enable --now gnome-wayland-computer-use-observer.socket 2>/dev/null || true

if [ -f "$HERMES_HOME/SOUL.md" ]; then
    sed -i 's#/scripts/capture\.sh" --media --screen#/scripts/observe.sh" --media --screen#g' "$HERMES_HOME/SOUL.md" || true
fi
state="${XDG_STATE_HOME:-$HOME/.local/state}/gnome-wayland-computer-use"
mkdir -p "$state"
chmod 700 "$state" 2>/dev/null || true
managed=false
[ -f "$state/cua-winrects-managed" ] && managed=true
python="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$python" ] || python="$(command -v python3)"
"$python" - "$state/ownership.json" "$managed" "$AGENT_ONLY" <<'PY'
import json, os, pathlib, sys
p = pathlib.Path(sys.argv[1])
managed = sys.argv[2] == 'true'
agent_only = sys.argv[3] == 'true'
d = {
    'schema': 'gwcu.ownership.v1',
    'winrects': {
        'managed': managed,
        'source': 'cua-package' if managed else 'external-or-absent',
    },
    'user_units': {
        'observer_socket': True,
        'observer_service': True,
        'cua_service': not agent_only,
    },
    'distro_foundation_owned': False,
}
t = p.with_suffix('.tmp')
t.write_text(json.dumps(d, separators=(',', ':')) + '\n')
os.chmod(t, 0o600)
os.replace(t, p)
PY
"$PRIMARY/scripts/profile.sh" refresh --quiet >/dev/null 2>&1 || true

echo ""
echo "Determinism layer ready."
echo "  observe:  $PRIMARY/scripts/observe.sh --machine --screen /tmp/screen.png"
echo "  profile:  $PRIMARY/scripts/profile.sh read --machine"
