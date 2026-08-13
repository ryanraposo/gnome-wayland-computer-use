#!/usr/bin/env bash
# capture.sh — direct one-shot visible-screen observation fallback.
# The warm ScreenCast broker lives in observer.py. This independent fallback
# uses only the XDG Screenshot portal: no focus mutation, raw input, or Cua calls.
set -euo pipefail
MEDIA=false
TIMING=false
REQUESTED_SCOPE=screen
OUT=""
START_MS=$(date +%s%3N 2>/dev/null || printf 0)
usage(){ echo "usage: $0 [--media] [--timing] [--desktop|--screen] [output.png]" >&2; }
while [ "$#" -gt 0 ]; do
    case "$1" in
        --media) MEDIA=true ;;
        --timing) TIMING=true ;;
        --desktop) REQUESTED_SCOPE=desktop ;;
        --screen) REQUESTED_SCOPE=screen ;;
        --help|-h) usage; exit 0 ;;
        -*) usage; exit 2 ;;
        *) [ -z "$OUT" ] || { usage; exit 2; }; OUT="$1" ;;
    esac
    shift
done
OUT="${OUT:-${XDG_RUNTIME_DIR:-/tmp}/gnome-wayland-screen-$(date +%s).png}"
mkdir -p "$(dirname "$OUT")"
TMP=$(mktemp "$(dirname "$OUT")/.capture.XXXXXX.png")
trap 'rm -f "$TMP"' EXIT
PYTHON="${GNOME_WAYLAND_SYSTEM_PYTHON:-/usr/bin/python3}"
[ -x "$PYTHON" ] || PYTHON="$(command -v python3 2>/dev/null || true)"
[ -n "$PYTHON" ] || { echo "capture_method=failed reason=python3_missing" >&2; exit 40; }

set +e
timeout 10 "$PYTHON" - "$TMP" <<'PY'
import os, signal, sys, uuid
import gi
gi.require_version('Gio','2.0')
from gi.repository import Gio, GLib
out=sys.argv[1]
bus=Gio.bus_get_sync(Gio.BusType.SESSION,None)
portal=Gio.DBusProxy.new_sync(bus,Gio.DBusProxyFlags.NONE,None,
    'org.freedesktop.portal.Desktop','/org/freedesktop/portal/desktop',
    'org.freedesktop.portal.Screenshot',None)
sender=bus.get_unique_name().lstrip(':').replace('.','_')
token='gwcu_'+uuid.uuid4().hex
expected=f'/org/freedesktop/portal/desktop/request/{sender}/{token}'
request_path=expected
loop=GLib.MainLoop(); response={}

def close_request():
    try:
        bus.call_sync('org.freedesktop.portal.Desktop',request_path,
            'org.freedesktop.portal.Request','Close',None,None,
            Gio.DBusCallFlags.NONE,1000,None)
    except Exception: pass

def halt(signum,_frame):
    close_request(); raise SystemExit(128+signum)
signal.signal(signal.SIGTERM,halt); signal.signal(signal.SIGINT,halt)

def got(_c,_s,_p,_i,_n,params):
    response['v']=params.unpack(); loop.quit()
sub=bus.signal_subscribe('org.freedesktop.portal.Desktop',
    'org.freedesktop.portal.Request','Response',expected,None,
    Gio.DBusSignalFlags.NONE,got)
try:
    opts={'handle_token':GLib.Variant('s',token),'interactive':GLib.Variant('b',False)}
    version=portal.get_cached_property('version')
    if version is not None and int(version.unpack())>=3:
        available=portal.get_cached_property('AvailableTargets')
        if available is None or int(available.unpack()) & 1:
            opts['target']=GLib.Variant('u',1)
    reply=portal.call_sync('Screenshot',GLib.Variant('(sa{sv})',('',opts)),
        Gio.DBusCallFlags.NONE,3000,None)
    unpacked=reply.unpack() if reply else ()
    if unpacked and isinstance(unpacked[0],str) and unpacked[0]!=expected:
        bus.signal_unsubscribe(sub); request_path=unpacked[0]
        sub=bus.signal_subscribe('org.freedesktop.portal.Desktop',
            'org.freedesktop.portal.Request','Response',request_path,None,
            Gio.DBusSignalFlags.NONE,got)
    timer=GLib.timeout_add_seconds(6,lambda:(loop.quit(),False)[1])
    loop.run()
    try: GLib.source_remove(timer)
    except Exception: pass
finally:
    bus.signal_unsubscribe(sub)
if 'v' not in response:
    close_request(); print('portal_status=failed api=screenshot reason=timeout',file=sys.stderr); raise SystemExit(40)
code,results=response['v']
if code:
    print(f'portal_status=denied api=screenshot code={code}',file=sys.stderr); raise SystemExit(20)
uri=results.get('uri')
if not uri:
    print('portal_status=failed api=screenshot reason=no-uri',file=sys.stderr); raise SystemExit(40)
Gio.File.new_for_uri(uri).copy(Gio.File.new_for_path(out),Gio.FileCopyFlags.OVERWRITE,None,None)
if not os.path.exists(out) or os.path.getsize(out)==0:
    print('portal_status=failed api=screenshot reason=empty-image',file=sys.stderr); raise SystemExit(40)
PY
RC=$?
set -e

if [ "$RC" -eq 20 ]; then echo "capture_method=portal-denied" >&2; exit 20; fi
if [ "$RC" -ne 0 ] || [ ! -s "$TMP" ]; then echo "capture_method=failed" >&2; exit 40; fi
mv -f "$TMP" "$OUT"; trap - EXIT
if [ "$REQUESTED_SCOPE" = desktop ]; then printf 'capture_scope=visible-screen requested=desktop\n' >&2; fi
if $TIMING; then
    now=$(date +%s%3N 2>/dev/null || printf 0)
    if [[ "$START_MS" =~ ^[0-9]+$ ]] && [[ "$now" =~ ^[0-9]+$ ]] && [ "$now" -ge "$START_MS" ]; then
        printf 'capture_elapsed_ms=%s\n' "$((now-START_MS))" >&2
    fi
fi
if $MEDIA; then printf 'MEDIA:%s\n' "$OUT"; printf 'capture_method=portal-screenshot\n' >&2
else printf 'capture_method=portal-screenshot\n'; fi
