#!/usr/bin/env bash
# capture.sh — native visible-screen capture for GNOME Wayland
#
# Hot path: XDG ScreenCast + PipeWire with a persistent restore token.
# Recovery: one-shot Screenshot portal -> legacy gnome-screenshot -> Shift+Print.
#
# There is intentionally no synthetic "desktop layer". --desktop remains a
# compatibility alias for the real visible display so older callers keep
# working without hiding windows, mutating Shell actors, or requiring an
# extension.
set -euo pipefail

MEDIA_MODE=false
TIMING_MODE=false
REQUESTED_SCOPE=screen
OUT=
CAPTURE_STARTED_MS=$(date +%s%3N 2>/dev/null || printf '0')

usage() {
    echo "usage: $0 [--media] [--timing] [--desktop|--screen] [output.png]" >&2
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --media) MEDIA_MODE=true ;;
        --timing) TIMING_MODE=true ;;
        --desktop) REQUESTED_SCOPE=desktop ;;
        --screen) REQUESTED_SCOPE=screen ;;
        -*) usage; exit 2 ;;
        *)
            if [ -n "$OUT" ]; then usage; exit 2; fi
            OUT="$1"
            ;;
    esac
    shift
done

OUT="${OUT:-${XDG_RUNTIME_DIR:-/tmp}/gnome-wayland-screen-$(date +%s).png}"
OUTDIR=$(dirname "$OUT")
mkdir -p "$OUTDIR"
TMP=$(mktemp "$OUTDIR/.capture.XXXXXX.png")
MARKER=$(mktemp "$OUTDIR/.capture-marker.XXXXXX")
trap 'rm -f "$TMP" "$MARKER"' EXIT

portal_python() {
    local python="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
    [ -x "$python" ] || python="$(command -v python3 2>/dev/null || true)"
    [ -n "$python" ] || return 1
    printf '%s\n' "$python"
}

capture_portal_screencast() {
    local python
    python=$(portal_python) || return 1

    timeout 30 "$python" - "$TMP" <<'PYEOF'
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

state_dir = pathlib.Path(
    os.environ.get('XDG_STATE_HOME', pathlib.Path.home() / '.local' / 'state')
) / 'gnome-wayland-computer-use'
token_file = state_dir / 'screencast-restore-token'

class PortalDenied(Exception):
    pass

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
            1000,
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

def request(method, signature, values, timeout_seconds=20):
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
            3000,
            None,
        )
        timeout_id = GLib.timeout_add_seconds(timeout_seconds, lambda: (loop.quit(), False)[1])
        loop.run()
        if GLib.MainContext.default().find_source_by_id(timeout_id):
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
        raise PortalDenied(f'{method} denied with code {code}')
    return results

try:
    created = request(
        'CreateSession',
        '(a{sv})',
        [{
            'session_handle_token': GLib.Variant('s', 'gwcu_session_' + uuid.uuid4().hex),
        }],
        5,
    )
    session_handle = created['session_handle']

    select_options = {
        'types': GLib.Variant('u', 1),
        'multiple': GLib.Variant('b', False),
    }

    cursor_modes = portal.get_cached_property('AvailableCursorModes')
    if cursor_modes is not None and cursor_modes.unpack() & 2:
        select_options['cursor_mode'] = GLib.Variant('u', 2)

    version_v = portal.get_cached_property('version')
    version = version_v.unpack() if version_v is not None else 0
    if version >= 4:
        select_options['persist_mode'] = GLib.Variant('u', 2)
        if token_file.is_file():
            restore_token = token_file.read_text(encoding='utf-8').strip()
            if restore_token:
                select_options['restore_token'] = GLib.Variant('s', restore_token)

    request('SelectSources', '(oa{sv})', [session_handle, select_options], 5)
    started = request('Start', '(osa{sv})', [session_handle, '', {}], 20)
    streams = started.get('streams', [])
    if not streams:
        raise RuntimeError('portal returned no streams')

    node_id, stream_props = streams[0]
    restore_token = started.get('restore_token')
    if restore_token:
        state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        tmp_token = token_file.with_suffix('.tmp')
        tmp_token.write_text(restore_token, encoding='utf-8')
        tmp_token.chmod(0o600)
        tmp_token.replace(token_file)

    reply, fd_list = portal.call_with_unix_fd_list_sync(
        'OpenPipeWireRemote',
        GLib.Variant('(oa{sv})', (session_handle, {})),
        Gio.DBusCallFlags.NONE,
        3000,
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
        5 * Gst.SECOND,
        Gst.MessageType.ERROR | Gst.MessageType.EOS,
    )
    pipeline.set_state(Gst.State.NULL)
    os.close(fd)

    if not message or message.type != Gst.MessageType.EOS:
        if message and message.type == Gst.MessageType.ERROR:
            error, debug = message.parse_error()
            raise RuntimeError(f'PipeWire capture failed: {error}; {debug or ""}')
        raise RuntimeError('PipeWire capture timed out')
    if not os.path.exists(out_path) or os.path.getsize(out_path) == 0:
        raise RuntimeError('capture produced an empty image')
except PortalDenied as exc:
    print(f'portal_status=denied api=screencast reason={exc}', file=sys.stderr)
    raise SystemExit(20)
except Exception as exc:
    print(f'portal_status=failed api=screencast reason={exc}', file=sys.stderr)
    raise SystemExit(1)
finally:
    cleanup()
PYEOF
}

capture_portal_screenshot() {
    local python
    python=$(portal_python) || return 1

    timeout 8 "$python" - "$TMP" <<'PYEOF'
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
            'org.freedesktop.portal.Desktop', request_path,
            'org.freedesktop.portal.Request', 'Close', None, None,
            Gio.DBusCallFlags.NONE, 1000, None,
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
    'org.freedesktop.portal.Desktop', 'org.freedesktop.portal.Request',
    'Response', request_path, None, Gio.DBusSignalFlags.NONE, on_response,
)
try:
    options = {
        'handle_token': GLib.Variant('s', token),
        'interactive': GLib.Variant('b', False),
    }
    version = portal.get_cached_property('version')
    if version is not None and version.unpack() >= 3:
        available = portal.get_cached_property('AvailableTargets')
        if available is None or available.unpack() & 1:
            options['target'] = GLib.Variant('u', 1)

    portal.call_sync(
        'Screenshot', GLib.Variant('(sa{sv})', ('', options)),
        Gio.DBusCallFlags.NONE, 3000, None,
    )
    timeout_id = GLib.timeout_add_seconds(5, lambda: (loop.quit(), False)[1])
    loop.run()
    if GLib.MainContext.default().find_source_by_id(timeout_id):
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

capture_gnome_screenshot() {
    local shell_major
    command -v gnome-screenshot >/dev/null 2>&1 || return 1
    if command -v gnome-shell >/dev/null 2>&1; then
        shell_major=$(gnome-shell --version 2>/dev/null | grep -oE '[0-9]+' | head -1)
        if [ -n "$shell_major" ] && [ "$shell_major" -ge 49 ]; then return 1; fi
    fi
    timeout 2 gnome-screenshot --file "$TMP" 2>/dev/null && [ -s "$TMP" ]
}

wait_for_new_screenshot() {
    local ss_dir="$1" latest="" attempt=0
    while [ "$attempt" -lt 40 ]; do
        latest=$(find "$ss_dir" -maxdepth 1 -type f -newer "$MARKER" -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr | head -1 | cut -d' ' -f2-)
        if [ -n "$latest" ] && [ -s "$latest" ]; then
            printf '%s\n' "$latest"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 0.025
    done
    return 1
}

capture_ydotool_printscreen() {
    local ss_dir="${HOME}/Pictures/Screenshots" latest
    command -v ydotool >/dev/null 2>&1 || return 1
    mkdir -p "$ss_dir"
    touch "$MARKER"
    timeout 1 ydotool key 42:1 99:1 99:0 42:0 2>/dev/null || return 1
    latest=$(wait_for_new_screenshot "$ss_dir") || return 1
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
    local method="$1" now_ms elapsed_ms
    if [ "$REQUESTED_SCOPE" = desktop ]; then
        printf 'capture_scope=visible-screen requested=desktop\n' >&2
    fi
    if "$TIMING_MODE"; then
        now_ms=$(date +%s%3N 2>/dev/null || printf '0')
        if [[ "$CAPTURE_STARTED_MS" =~ ^[0-9]+$ ]] && [[ "$now_ms" =~ ^[0-9]+$ ]] && \
           [ "$CAPTURE_STARTED_MS" -gt 0 ] && [ "$now_ms" -ge "$CAPTURE_STARTED_MS" ]; then
            elapsed_ms=$((now_ms - CAPTURE_STARTED_MS))
            printf 'capture_elapsed_ms=%s\n' "$elapsed_ms" >&2
        fi
    fi
    if "$MEDIA_MODE"; then
        printf 'MEDIA:%s\n' "$OUT"
        printf 'capture_method=%s\n' "$method" >&2
    else
        printf 'capture_method=%s\n' "$method"
    fi
}

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

rm -f "$TMP"
if capture_gnome_screenshot; then
    finish_capture
    report_capture "gnome-screenshot"
    exit 0
fi

rm -f "$TMP"
if capture_ydotool_printscreen; then
    finish_capture
    report_capture "ydotool-shift-print"
    exit 0
fi

echo "capture_method=failed" >&2
exit 1
