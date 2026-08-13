# Performance Notes

Performance is measured end-to-end in agent round-trips, not just script runtime.

## Fast path

```text
known target
→ one Cua target/window state
→ AX or PX from that state
→ deterministic action span
→ verify only when the next decision depends on it
```

The project should add essentially zero control-path latency beyond the skill
instruction itself. Cua is already the control runtime.

## Whole-screen capture

Whole-screen observation is intentionally separate and lazy:

- the systemd socket is always cheap;
- the broker starts only on a capture request;
- one portal session and PipeWire remote stay warm for a bounded task burst;
- each request asks for a fresh frame without reopening portal consent;
- idle expiry releases the stream.

The direct `capture.sh` path remains available for broker/service failures and
uses the XDG Screenshot portal only.

## Avoided costs

The Cua-native architecture removes several historical costs entirely:

- no `ydotoold` startup;
- no uinput permission probing;
- no custom Cua daemon lifecycle;
- no duplicated AT-SPI or WinRects investigations;
- no toolkit-driven focus deliberation;
- no fallback ladder invented by the model.

## Release measurements

Live GNOME 50 release smoke should record:

- cold first ScreenCast consent latency;
- restored-session cold capture;
- warm broker p50/p95 capture latency;
- broker idle/restart latency;
- known-target Cua state latency;
- semantic background action latency;
- exact foreground escalation latency;
- pixel-only target action latency.

The meaningful benchmark is the number of model/tool boundaries required to
finish a representative desktop task correctly.
