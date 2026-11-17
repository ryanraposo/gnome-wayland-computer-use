#!/usr/bin/env bash
# cua-autostart.sh — render and retire the GWCU-managed Cua logon daemon unit.
#
# This helper owns only the unit file on disk. It never decides policy: the
# installer enables and live-proves the daemon, and teardown preserves anything
# it did not create. Keeping file ownership here makes both paths testable
# without a running systemd manager.
set -euo pipefail

UNIT="gnome-wayland-computer-use-cua-driver.service"
MARKER='# gnome-wayland-computer-use managed unit'
PYTHON="${GWCU_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
[ -n "$PYTHON" ] || { printf 'error: python3 is required\n' >&2; exit 2; }

usage() {
    cat <<'HELP'
Usage: cua-autostart.sh <command> [args]

  install <template> <unit-dir> <driver>  Render the unit for <driver> unless an
                                          unmanaged unit already owns that path.
                                          Prints managed|external.
  remove <unit-dir>                       Remove only a GWCU-managed unit.
                                          Prints removed|preserved|absent.
  self-test                               Render/classify/remove in a temp dir.
HELP
}

unit_path() { printf '%s/%s' "$1" "$UNIT"; }

classify() {
    local path
    path=$(unit_path "$1")
    [ -e "$path" ] || { printf 'absent'; return 0; }
    if [ -f "$path" ] && grep -Fq "$MARKER" "$path"; then printf 'managed'
    else printf 'external'; fi
}

render() {
    local template=$1 out=$2 driver=$3 tmp
    [ -f "$template" ] || { printf 'error: unit template missing: %s\n' "$template" >&2; return 20; }
    case "$driver" in /*) ;; *) printf 'error: driver path must be absolute: %s\n' "$driver" >&2; return 20;; esac
    tmp=$(mktemp "${out}.XXXXXX")
    "$PYTHON" - "$template" "$tmp" "$driver" <<'PY' || { rm -f "$tmp"; exit 21; }
import pathlib,sys
template,out,driver=sys.argv[1:4]
text=pathlib.Path(template).read_text()
if '%CUA_DRIVER_BIN%' not in text:
    raise SystemExit('unit template lost its Cua driver placeholder')
rendered=text.replace('%CUA_DRIVER_BIN%',driver)
if '%CUA_DRIVER_BIN%' in rendered or driver not in rendered:
    raise SystemExit('unit render did not bind the qualified driver')
pathlib.Path(out).write_text(rendered)
PY
    chmod 644 "$tmp"
    mv -f "$tmp" "$out"
}

install_unit() {
    local template=$1 unit_dir=$2 driver=$3 state path
    [ "$#" -eq 3 ] || { usage >&2; exit 2; }
    state=$(classify "$unit_dir")
    if [ "$state" = external ]; then
        printf '%s\n' external
        return 0
    fi
    mkdir -p "$unit_dir"
    path=$(unit_path "$unit_dir")
    render "$template" "$path" "$driver" || return $?
    printf '%s\n' managed
}

remove_unit() {
    local unit_dir=$1 path state
    [ "$#" -eq 1 ] || { usage >&2; exit 2; }
    state=$(classify "$unit_dir")
    [ "$state" = absent ] && { printf '%s\n' absent; return 0; }
    path=$(unit_path "$unit_dir")
    if [ "$state" = managed ]; then rm -f "$path"; printf '%s\n' removed
    else printf '%s\n' preserved; fi
}

self_test() {
    SELFTEST_TMP=$(mktemp -d); trap 'rm -rf "$SELFTEST_TMP"' EXIT
    local template driver state path
    tmp="$SELFTEST_TMP"
    template="$tmp/template.service"
    cat >"$template" <<'TPL'
# gnome-wayland-computer-use managed unit
[Unit]
Description=GWCU-managed Cua Driver logon daemon
PartOf=graphical-session.target

[Service]
ExecStart="%CUA_DRIVER_BIN%" serve
Restart=on-failure

[Install]
WantedBy=graphical-session.target
TPL
    driver="$tmp/cua-driver"
    mkdir -p "$tmp/mock-unit-dir"

    state=$(install_unit "$template" "$tmp/mock-unit-dir" "$driver")
    [ "$state" = managed ] || { printf 'self-test: fresh install was not managed\n' >&2; return 1; }
    path=$(unit_path "$tmp/mock-unit-dir")
    grep -Fq "$MARKER" "$path" || { printf 'self-test: managed marker missing\n' >&2; return 1; }
    grep -Fq "ExecStart=\"$driver\" serve" "$path" || { printf 'self-test: driver not bound\n' >&2; return 1; }
    ! grep -Fq '%CUA_DRIVER_BIN%' "$path" || { printf 'self-test: placeholder survived\n' >&2; return 1; }

    state=$(remove_unit "$tmp/mock-unit-dir")
    [ "$state" = removed ] && [ ! -e "$path" ] || { printf 'self-test: managed unit not removed\n' >&2; return 1; }

    cat >"$path" <<'EXT'
[Unit]
Description=User-owned Cua daemon
[Service]
ExecStart=/usr/bin/cua-driver serve
EXT
    state=$(install_unit "$template" "$tmp/mock-unit-dir" "$driver")
    [ "$state" = external ] || { printf 'self-test: external unit not detected\n' >&2; return 1; }
    grep -Fq 'Description=User-owned Cua daemon' "$path" || { printf 'self-test: external unit was overwritten\n' >&2; return 1; }
    state=$(remove_unit "$tmp/mock-unit-dir")
    [ "$state" = preserved ] && [ -f "$path" ] || { printf 'self-test: external unit not preserved\n' >&2; return 1; }

    printf 'cua-autostart self-test: ok\n'
}

case "${1:-}" in
    install) shift; install_unit "$@" ;;
    remove) shift; remove_unit "$@" ;;
    self-test) self_test ;;
    --help|-h|help) usage ;;
    *) usage >&2; exit 2 ;;
esac
