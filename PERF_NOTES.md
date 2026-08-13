# Performance Notes

The performance target is end-to-end computer-use latency, not the speed of one
primitive in isolation.

> **Route once → cheapest truthful evidence → deterministic action span → verify at the next decision boundary.**

## Observation latency

### Hot path: ScreenCast + PipeWire

`capture.sh` creates an XDG ScreenCast session, restores the previously approved
monitor when a restore token exists, opens the portal-scoped PipeWire remote,
and pulls one PNG frame.

Ubuntu 26.04 GNOME already ships PipeWire/WirePlumber as desktop foundation. The
installer verifies that baseline and repairs missing official portal/PipeWire/
GStreamer packages only on incomplete hosts; it does not treat PipeWire as a
project daemon.

The first capture can be much slower because monitor-sharing consent is a real
human permission boundary. Measure warm capture separately from first-use
consent.

### Recovery

The one-shot Screenshot portal is recovery, not the hot path. Legacy
`gnome-screenshot` is skipped where modern GNOME no longer exposes a reliable
path. Shift+Print through `ydotool` remains the final capture fallback.

## Control latency

AT-SPI is cheapest when semantics exist. For Cua-backed GNOME control, WinRects
can eliminate repeated uncertain geometry/focus discovery by supplying the
runtime with authoritative Mutter geometry and verified activation.

That does **not** make WinRects part of screen capture. Keeping ScreenCast and
Cua control independent preserves two useful failure domains:

```text
Cua / WinRects degraded  → ScreenCast observation can survive
ScreenCast degraded      → Cua control/capture paths may survive
```

Real redundancy is cheaper than duplicated mechanisms chained together.

## Pixel-only surfaces

Do not measure failed semantic discovery as productive latency. A visible
GLFW/Vulkan/canvas window with no AT-SPI contract should move to pixels quickly.

If Cua can resolve its GNOME window, pair the fresh image with WinRects-backed
geometry and use verified foreground only when required. If the target cannot be
resolved safely, spend latency on foreground discovery—not repeated AX probes or
blind raw input.

## Decision-boundary savings

The largest wins usually come from removing unnecessary observation/model
round-trips:

- resolve app/window identity once;
- AX before pixels for accessible state;
- one complete typing call;
- one complete shortcut;
- semantic value-setting instead of menu choreography;
- useful scroll distances;
- no screenshot between deterministic click → type;
- no screenshot between verified type → known submit;
- no ritual recapture when structured read-back already proves the state;
- no repeated focus guessing when Cua has verified target activation.

## Measure separately

1. first ScreenCast permission;
2. warm ScreenCast restore + PipeWire frame;
3. fallback capture;
4. semantic background action;
5. target-addressed pixel action;
6. verified foreground activation + delivery;
7. `ydotool` recovery;
8. structured refusal / target rediscovery.

Combining these into one average hides the reason a workflow is slow.

## Regression expectations

Tests should guard ordering and boundaries rather than brittle CI wall-clock
numbers:

- ScreenCast precedes Screenshot;
- consent denial is terminal;
- restore tokens rotate;
- `capture.sh` contains no WinRects call or project Shell service;
- Cua's helper installer is used only for Cua-backed GNOME setup;
- agent-only setup does not acquire Cua for WinRects;
- WinRects installed/active/reload-required states are distinct;
- pre-existing WinRects ownership is preserved;
- failed capture preserves an existing output;
- runtime guidance moves pixel-only visible surfaces to pixels quickly;
- focus-bound delivery is verified before input.
