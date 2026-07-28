#!/usr/bin/env bash
# capture.sh — capture a screenshot on GNOME Wayland
# Desktop: focus-free GNOME Shell desktop-layer capture → reversible
# show-desktop/Shift+Print compatibility path.
# Screen: gnome-screenshot → Screenshot portal → Shift+Print.
set -euo pipefail

MEDIA_MODE=false
CAPTURE_MODE=desktop
OUT=
CAPTURE_PROOF=
while [ "$#" -gt 0 ]; do
    case "$1" in
        --media) MEDIA_MODE=true ;;
        --desktop) CAPTURE_MODE=desktop ;;
        --screen) CAPTURE_MODE=screen ;;
        -*) echo "usage: $0 [--media] [--desktop|--screen] [output.png]" >&2; exit 2 ;;
        *)
            if [ -n "$OUT" ]; then
                echo "usage: $0 [--media] [--desktop|--screen] [output.png]" >&2
                exit 2
            fi
            OUT="$1"
            ;;
    esac
    shift
done

OUT="${OUT:-${XDG_RUNTIME_DIR:-/tmp}/hermes-${CAPTURE_MODE}-$(date +%s).png}"
if [ "$CAPTURE_MODE" != desktop ] && [ "$CAPTURE_MODE" != screen ]; then
    echo "capture_mode=invalid" >&2
    exit 2
fi
OUTDIR=$(dirname "$OUT")
mkdir -p "$OUTDIR"
TMP=$(mktemp "$OUTDIR/.capture.XXXXXX.png")
MARKER=$(mktemp "$OUTDIR/.capture-marker.XXXXXX")
trap 'rm -f "$TMP" "$MARKER"' EXIT

capture_gnome_shell_desktop() {
    local result
    command -v gdbus >/dev/null 2>&1 || return 1
    result=$(timeout 10 gdbus call --session \
        --dest io.github.ryanraposo.GnomeWaylandDesktopCapture \
        --object-path /io/github/ryanraposo/GnomeWaylandDesktopCapture \
        --method io.github.ryanraposo.GnomeWaylandDesktopCapture.CaptureDesktop \
        "$TMP" 2>/dev/null) || return 1
    [ -s "$TMP" ] || return 1
    case "$result" in
        "(true,"*)
            CAPTURE_PROOF="$result"
            return 0
            ;;
        *) return 1 ;;
    esac
}

capture_gnome_screenshot() {
    local shell_major
    command -v gnome-screenshot >/dev/null 2>&1 || return 1
    if command -v gnome-shell >/dev/null 2>&1; then
        shell_major=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
        if [ -n "$shell_major" ] && [ "$shell_major" -ge 49 ]; then
            return 1
        fi
    fi
    timeout 5 gnome-screenshot --file "$TMP" 2>/dev/null && [ -s "$TMP" ]
}

capture_portal_screenshot() {
    local portal_python="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
    [ -x "$portal_python" ] || portal_python="$(command -v python3 2>/dev/null || true)"
    [ -n "$portal_python" ] || return 1
    timeout 15 "$portal_python" - "$TMP" << 'PYEOF'
import os
import signal
import sys
import uuid

import gi
gi.require_version('Gio', '2.0')
from gi.repository import Gio, GLib

out_path = sys.argv[1]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
portal = Gio.DBusProxy.new_sync(
    bus,
    Gio.DBusProxyFlags.NONE,
    None,
    'org.freedesktop.portal.Desktop',
    '/org/freedesktop/portal/desktop',
    'org.freedesktop.portal.Screenshot',
    None,
)

sender = bus.get_unique_name().lstrip(':').replace('.', '_')
token = 'gwcu_' + uuid.uuid4().hex
request_path = f'/org/freedesktop/portal/desktop/request/{sender}/{token}'
loop = GLib.MainLoop()
response = {}

def close_request():
    try:
        bus.call_sync(
            'org.freedesktop.portal.Desktop',
            request_path,
            'org.freedesktop.portal.Request',
            'Close',
            None,
            None,
            Gio.DBusCallFlags.NONE,
            2000,
            None,
        )
    except Exception:
        pass

def on_signal(signum, _frame):
    close_request()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

def on_response(_connection, _sender, _path, _interface, _signal, parameters):
    response['value'] = parameters.unpack()
    loop.quit()

subscription = bus.signal_subscribe(
    'org.freedesktop.portal.Desktop',
    'org.freedesktop.portal.Request',
    'Response',
    request_path,
    None,
    Gio.DBusSignalFlags.NONE,
    on_response,
)
try:
    options = {
        'handle_token': GLib.Variant('s', token),
        'interactive': GLib.Variant('b', False),
    }
    version = portal.get_cached_property('version')
    if version is not None and version.unpack() >= 3:
        options['target'] = GLib.Variant('u', 1)
    portal.call_sync(
        'Screenshot',
        GLib.Variant('(sa{sv})', ('', options)),
        Gio.DBusCallFlags.NONE,
        5000,
        None,
    )
    timeout_id = GLib.timeout_add_seconds(10, lambda: (loop.quit(), False)[1])
    loop.run()
    GLib.source_remove(timeout_id)
finally:
    bus.signal_unsubscribe(subscription)

if 'value' not in response:
    close_request()
    print('portal_status=failed api=screenshot reason=timeout', file=sys.stderr)
    raise SystemExit(1)

code, results = response['value']
if code != 0:
    print(f'portal_status=denied api=screenshot code={code}', file=sys.stderr)
    raise SystemExit(20)

uri = results.get('uri')
if not uri:
    print('portal_status=failed api=screenshot reason=no-uri', file=sys.stderr)
    raise SystemExit(1)

source = Gio.File.new_for_uri(uri)
target = Gio.File.new_for_path(out_path)
source.copy(target, Gio.FileCopyFlags.OVERWRITE, None, None)
if not os.path.exists(out_path) or os.path.getsize(out_path) == 0:
    print('portal_status=failed api=screenshot reason=empty-image', file=sys.stderr)
    raise SystemExit(1)
PYEOF
}

capture_portal_screencast() {
    local portal_python="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
    [ -x "$portal_python" ] || portal_python="$(command -v python3 2>/dev/null || true)"
    [ -n "$portal_python" ] || return 1
    timeout 60 "$portal_python" - "$TMP" << 'PYEOF'
import os
import pathlib
import signal
import sys
import uuid

import gi
gi.require_version('Gio', '2.0')
gi.require_version('Gst', '1.0')
from gi.repository import Gio, GLib, Gst

Gst.init(None)

out_path = sys.argv[1]
bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
portal = Gio.DBusProxy.new_sync(
    bus,
    Gio.DBusProxyFlags.NONE,
    None,
    'org.freedesktop.portal.Desktop',
    '/org/freedesktop/portal/desktop',
    'org.freedesktop.portal.ScreenCast',
    None,
)

sender = bus.get_unique_name().lstrip(':').replace('.', '_')
session_handle = None
active_request_path = None

def close_dbus_object(path, interface):
    if not path:
        return
    try:
        bus.call_sync(
            'org.freedesktop.portal.Desktop',
            path,
            interface,
            'Close',
            None,
            None,
            Gio.DBusCallFlags.NONE,
            2000,
            None,
        )
    except Exception:
        pass

def cleanup():
    close_dbus_object(active_request_path, 'org.freedesktop.portal.Request')
    close_dbus_object(session_handle, 'org.freedesktop.portal.Session')

def on_signal(signum, _frame):
    cleanup()
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, on_signal)
signal.signal(signal.SIGINT, on_signal)

def request(method, signature, values):
    global active_request_path
    token = 'gwcu_' + uuid.uuid4().hex
    request_path = f'/org/freedesktop/portal/desktop/request/{sender}/{token}'
    active_request_path = request_path
    loop = GLib.MainLoop()
    response = {}

    def on_response(_connection, _sender, _path, _interface, _signal, parameters):
        response['value'] = parameters.unpack()
        loop.quit()

    subscription = bus.signal_subscribe(
        'org.freedesktop.portal.Desktop',
        'org.freedesktop.portal.Request',
        'Response',
        request_path,
        None,
        Gio.DBusSignalFlags.NONE,
        on_response,
    )
    try:
        values[-1]['handle_token'] = GLib.Variant('s', token)
        portal.call_sync(
            method,
            GLib.Variant(signature, tuple(values)),
            Gio.DBusCallFlags.NONE,
            5000,
            None,
        )
        timeout_id = GLib.timeout_add_seconds(55, lambda: (loop.quit(), False)[1])
        loop.run()
        GLib.source_remove(timeout_id)
    finally:
        bus.signal_unsubscribe(subscription)

    if 'value' not in response:
        close_dbus_object(request_path, 'org.freedesktop.portal.Request')
        active_request_path = None
        raise RuntimeError(f'{method} timed out')
    code, results = response['value']
    active_request_path = None
    if code != 0:
        print(f'portal_status=denied method={method} code={code}', file=sys.stderr)
        raise SystemExit(20)
    return results

created = request(
    'CreateSession',
    '(a{sv})',
    [{
        'session_handle_token': GLib.Variant('s', 'gwcu_session_' + uuid.uuid4().hex),
    }],
)
session_handle = created['session_handle']

try:
    state_dir = pathlib.Path(
        os.environ.get('XDG_STATE_HOME', pathlib.Path.home() / '.local' / 'state')
    ) / 'gnome-wayland-computer-use'
    token_file = state_dir / 'portal-restore-token'
    select_options = {
        'types': GLib.Variant('u', 1),
        'multiple': GLib.Variant('b', False),
        'cursor_mode': GLib.Variant('u', 2),
        'persist_mode': GLib.Variant('u', 2),
    }
    if token_file.is_file():
        select_options['restore_token'] = GLib.Variant('s', token_file.read_text().strip())

    request('SelectSources', '(oa{sv})', [session_handle, select_options])
    started = request('Start', '(osa{sv})', [session_handle, '', {}])
    streams = started.get('streams', [])
    if not streams:
        raise RuntimeError('portal returned no streams')
    node_id = streams[0][0]

    restore_token = started.get('restore_token')
    if restore_token:
        state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        token_file.write_text(restore_token)
        token_file.chmod(0o600)

    reply, fd_list = portal.call_with_unix_fd_list_sync(
        'OpenPipeWireRemote',
        GLib.Variant('(oa{sv})', (session_handle, {})),
        Gio.DBusCallFlags.NONE,
        5000,
        None,
        None,
    )
    fd = fd_list.get(reply.unpack()[0])

    pipeline = Gst.parse_launch(
        f'pipewiresrc fd={fd} path={node_id} do-timestamp=true num-buffers=1 ! '
        f'videoconvert ! pngenc ! filesink location={GLib.shell_quote(out_path)}'
    )
    pipeline_bus = pipeline.get_bus()
    pipeline.set_state(Gst.State.PLAYING)
    message = pipeline_bus.timed_pop_filtered(
        10 * Gst.SECOND,
        Gst.MessageType.ERROR | Gst.MessageType.EOS,
    )
    pipeline.set_state(Gst.State.NULL)
    os.close(fd)

    if not message or message.type != Gst.MessageType.EOS:
        raise RuntimeError('PipeWire capture failed')
    if not os.path.exists(out_path) or os.path.getsize(out_path) == 0:
        raise RuntimeError('capture produced an empty image')
finally:
    cleanup()
PYEOF
}

capture_ydotool_printscreen() {
    local ss_dir="${HOME}/Pictures/Screenshots"
    mkdir -p "$ss_dir"
    local latest

    command -v ydotool >/dev/null 2>&1 || return 1
    touch "$MARKER"
    # GNOME binds Shift+Print to a direct full-screen capture. Plain Print opens
    # the screenshot UI, whose remembered mode may be "window" or "selection".
    timeout 3 ydotool key 42:1 99:1 99:0 42:0 2>/dev/null || return 1
    sleep 1.5
    latest=$(find "$ss_dir" -maxdepth 1 -type f -newer "$MARKER" -printf '%T@ %p\n' \
        | sort -nr | head -1 | cut -d' ' -f2-)
    [ -n "$latest" ] || return 1
    cp "$latest" "$TMP"
    rm -f "$latest"
    [ -s "$TMP" ]
}

get_window_rects() {
    timeout 3 gdbus call --session \
        --dest org.cua.WinRects \
        --object-path /org/cua/WinRects \
        --method org.cua.WinRects.GetRects 2>/dev/null
}

toggle_show_desktop() {
    timeout 3 ydotool key 125:1 32:1 32:0 125:0 2>/dev/null
}

capture_ydotool_desktop() {
    local ss_dir="${HOME}/Pictures/Screenshots"
    local latest toggled=false capture_rc=0 before_state= after_state=

    command -v ydotool >/dev/null 2>&1 || return 1
    mkdir -p "$ss_dir"

    before_state=$(get_window_rects || true)
    if [ -z "$before_state" ] || [[ "$before_state" == *'"visible":true'* ]]; then
        toggle_show_desktop || return 1
        toggled=true
        sleep 0.4
    fi

    touch "$MARKER"
    timeout 3 ydotool key 42:1 99:1 99:0 42:0 2>/dev/null || capture_rc=$?
    sleep 1.5

    if "$toggled"; then
        toggle_show_desktop || capture_rc=1
        sleep 0.2
    fi
    [ "$capture_rc" -eq 0 ] || return 1
    if [ -n "$before_state" ]; then
        after_state=$(get_window_rects || true)
        [ "$after_state" = "$before_state" ] || return 1
        CAPTURE_PROOF="show-desktop-restored=true"
    else
        CAPTURE_PROOF="show-desktop-restored=unverified"
    fi

    latest=$(find "$ss_dir" -maxdepth 1 -type f -newer "$MARKER" -printf '%T@ %p\n' \
        | sort -nr | head -1 | cut -d' ' -f2-)
    [ -n "$latest" ] || return 1
    cp "$latest" "$TMP"
    rm -f "$latest"
    [ -s "$TMP" ]
}

finish_capture() {
    mv -f "$TMP" "$OUT"
    trap - EXIT
    rm -f "$MARKER"
}

report_capture() {
    local method="$1"
    if [ -n "$CAPTURE_PROOF" ]; then
        printf 'capture_proof=%s\n' "$CAPTURE_PROOF" >&2
    fi
    if "$MEDIA_MODE"; then
        printf 'MEDIA:%s\n' "$OUT"
        printf 'capture_method=%s\n' "$method" >&2
    else
        printf 'capture_method=%s\n' "$method"
    fi
}

if [ "$CAPTURE_MODE" = desktop ]; then
    if capture_gnome_shell_desktop; then
        finish_capture
        report_capture "gnome-shell-desktop"
        exit 0
    fi

    rm -f "$TMP"
    if capture_ydotool_desktop; then
        finish_capture
        report_capture "ydotool-show-desktop"
        exit 0
    fi

    echo "capture_method=failed mode=desktop" >&2
    exit 1
fi

if capture_gnome_screenshot; then
    finish_capture
    report_capture "gnome-screenshot"
    exit 0
fi

rm -f "$TMP"
portal_rc=0
capture_portal_screenshot || portal_rc=$?
if [ "$portal_rc" -eq 0 ] && [ -s "$TMP" ]; then
    finish_capture
    report_capture "portal-screenshot"
    exit 0
fi
if [ "$portal_rc" -eq 20 ]; then
    echo "capture_method=portal-denied" >&2
    exit 1
fi

if [ "${GNOME_WAYLAND_ENABLE_SCREENCAST_FALLBACK:-0}" = "1" ]; then
    rm -f "$TMP"
    portal_rc=0
    capture_portal_screencast || portal_rc=$?
    if [ "$portal_rc" -eq 0 ] && [ -s "$TMP" ]; then
        finish_capture
        report_capture "portal-screencast"
        exit 0
    fi
    if [ "$portal_rc" -eq 20 ]; then
        echo "capture_method=portal-denied" >&2
        exit 1
    fi
fi

rm -f "$TMP"
if capture_ydotool_printscreen; then
    finish_capture
    report_capture "ydotool-shift-print"
    exit 0
fi

echo "capture_method=failed" >&2
exit 1
