#!/usr/bin/env bash
# capture.sh — capture a screenshot on GNOME Wayland
# Fallback chain: gnome-screenshot → portal (Python+gi) → ydotool fake PrintScreen
set -euo pipefail

OUT="${1:-/tmp/screen.png}"
OUTDIR=$(dirname "$OUT")
mkdir -p "$OUTDIR"

capture_gnome_screenshot() {
    gnome-screenshot --file "$OUT" 2>/dev/null && [ -s "$OUT" ]
}

capture_portal() {
    python3 - "$OUT" << 'PYEOF' 2>/dev/null
import gi, os, sys
gi.require_version('Gst', '1.0')
gi.require_version('GstApp', '1.0')
from gi.repository import Gst, GLib

Gst.init(None)

out_path = sys.argv[1]
pipe_str = (
    'pipewiresrc ! '
    'videoconvert ! '
    'pngenc ! '
    'filesink location=%s' % out_path
)

pipeline = Gst.parse_launch(pipe_str)
bus = pipeline.get_bus()
pipeline.set_state(Gst.State.PLAYING)

msg = bus.timed_pop_filtered(
    Gst.CLOCK_TIME_NONE,
    Gst.MessageType.ERROR | Gst.MessageType.EOS
)
pipeline.set_state(Gst.State.NULL)

if msg and msg.type == Gst.MessageType.EOS and os.path.exists(out_path) and os.path.getsize(out_path) > 0:
    sys.exit(0)
sys.exit(1)
PYEOF
}

capture_ydotool_printscreen() {
    local ss_dir="${HOME}/Pictures/Screenshots"
    mkdir -p "$ss_dir"
    local before before_count after after_count latest

    before=$(ls -1 "$ss_dir" 2>/dev/null | wc -l)
    ydotool key 99:1 99:0 2>/dev/null || return 1
    sleep 1.5
    after=$(ls -1 "$ss_dir" 2>/dev/null | wc -l)

    if [ "$after" -gt "$before" ]; then
        latest=$(ls -1t "$ss_dir" | head -1)
        cp "$ss_dir/$latest" "$OUT"
        rm -f "$ss_dir/$latest"
        [ -s "$OUT" ]
    else
        return 1
    fi
}

if capture_gnome_screenshot; then
    echo "capture_method=gnome-screenshot"
    exit 0
fi

if capture_portal; then
    echo "capture_method=portal"
    exit 0
fi

if capture_ydotool_printscreen; then
    echo "capture_method=ydotool-printscreen"
    exit 0
fi

echo "capture_method=failed" >&2
exit 1
