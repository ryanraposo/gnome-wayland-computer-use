# Performance Notes

The performance target is end-to-end computer-use latency, not the speed of an
individual primitive in isolation.

## Rule

> **Pay for evidence only when it changes the next decision.**

An AX observation can be cheaper and stronger than a screenshot. A visible
screen is stronger than repeated AX discovery for a GLFW/Vulkan surface. A
structured action verdict can be stronger than an immediate recapture.

## Capture latency model

### Hot path: ScreenCast + PipeWire

`capture.sh` creates an XDG ScreenCast session, restores the previously approved
monitor when a restore token exists, opens the portal-scoped PipeWire remote,
and pulls one PNG frame.

On portal v4+, `persist_mode=2` allows the portal to return a restore token. The
token is single-use and is replaced after each successful restoration.

The first capture can be much slower because monitor-sharing consent is a real
human permission boundary. Measure warm capture separately from first-use
consent.

### Recovery: Screenshot portal

The one-shot Screenshot portal is deliberately not the hot path. It remains a
simple, trustworthy recovery surface, but on some GNOME 50 / Ubuntu 26 hosts it
can take several seconds. Treat that as fallback latency, not the expected
steady-state budget.

### Legacy and hardware recovery

`gnome-screenshot` is skipped on GNOME 49+ because its old Shell path is not a
reliable modern interface. Shift+Print through `ydotool` is the final capture
fallback and uses polling for screenshot-file creation instead of fixed sleeps.

## Measure

```bash
CAPTURE="$HOME/.agents/skills/gnome-wayland-computer-use/scripts/capture.sh"

# First-use / permission-boundary measurement
"$CAPTURE" --timing --screen /tmp/first.png

# Warm restored-session measurement
"$CAPTURE" --timing --screen /tmp/warm.png

# Repeat a few warm samples
for i in 1 2 3 4 5; do
  "$CAPTURE" --timing --screen "/tmp/warm-$i.png"
done
```

`capture_elapsed_ms=N` is emitted on stderr.

When diagnosing a slow capture, also run:

```bash
~/.agents/skills/gnome-wayland-computer-use/scripts/diagnose.sh
```

Look specifically for:

- ScreenCast portal readiness;
- PipeWire/GStreamer readiness;
- whether a restore token is cached;
- accidental fallback to the Screenshot portal;
- legacy project capture extension absence.

## Interaction latency

The largest wins usually come from removing unnecessary observation/model
round-trips:

- resolve app identity once;
- AX before pixels for accessible text/state;
- one complete typing call;
- one complete shortcut;
- semantic value-setting instead of menu choreography;
- useful scroll distances;
- no screenshot between deterministic click → type;
- no screenshot between verified type → known submit;
- no ritual recapture when structured read-back already proves the state.

## Pixel-only surfaces

Do not measure failed semantic discovery as if it were productive latency.
For a GLFW/Vulkan/canvas surface that has no AT-SPI contract, repeated
`list_windows`/AX/SOM attempts are pure overhead.

Switch to the visible screen once the semantic path has proved unavailable.
The next relevant latency budget is screen capture + visual grounding +
coordinate delivery.

## Budgets are separated

Keep these measurements distinct:

1. **first permission** — human chooser time;
2. **warm capture** — restored ScreenCast + PipeWire frame;
3. **fallback capture** — Screenshot portal or hardware shortcut;
4. **semantic action** — runtime action + structured verification;
5. **pixel action** — capture + visual grounding + coordinate delivery;
6. **recovery** — foreground selection, fresh capture, or hardware fallback.

Combining them into one average hides the reason a workflow is slow.

## Regression expectations

Tests should guard architecture and ordering rather than brittle wall-clock
numbers in CI:

- ScreenCast is attempted before Screenshot;
- a denied ScreenCast permission does not open another capture UI;
- technical ScreenCast failure can fall back;
- `--desktop` does not invoke a window-hiding transaction;
- no WinRects or project Shell-extension dependency is present;
- failed capture preserves an existing output;
- timing mode preserves the normal stdout/media contract;
- runtime guidance moves inaccessible visible surfaces to pixels quickly.
