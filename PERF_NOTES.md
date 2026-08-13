# Performance Notes

Performance is measured in **agent round-trips**, not only milliseconds.

## First-use call budget

The repository should contribute almost no setup chatter before useful Cua work.

| Situation | GWCU calls before first useful Cua state |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen request | **1** — `observe.sh` |

The important optimization is structural: several local script/process calls can
happen inside one terminal invocation without creating several model/tool turns.

## Fast path

```text
known target
→ one Cua target/window state
→ AX or PX from that state
→ deterministic action span
→ verify only when the next decision depends on it
```

There are no GWCU diagnostics, update checks, launcher scans, or whole-screen
captures on that path.

## Script-script composition

`profile.sh route` and `profile.sh recover` are deliberately asymmetric:

- `route NAME` uses cached state opportunistically and resolves launcher/PWA
  identity locally. A missing launcher is not treated as a missing live window;
  the original target goes straight to Cua.
- `recover` is used only after a host contradiction. It reads the cached profile
  and refreshes through `diagnose.sh` only when stale/missing, all inside one
  outer agent call.

This converts branching model deliberation into structured `gwcu.route.v1`
information.

## Whole-screen capture

Whole-screen observation remains separate and lazy:

- the systemd socket is cheap;
- the broker starts only on a capture request;
- one portal session and PipeWire remote stay warm for a bounded task burst;
- each request asks for a fresh frame without reopening the capture chain;
- idle expiry releases the stream.

The direct `capture.sh` path remains a Screenshot-portal-only fallback.

## Avoided costs

The Cua-native architecture removes historical work entirely:

- no `ydotoold` startup;
- no uinput permission probing;
- no custom Cua daemon lifecycle;
- no duplicated AT-SPI or WinRects investigation;
- no toolkit-driven focus deliberation;
- no model-invented fallback ladder;
- no model-driven `profile read → refresh → diagnose` sequence.

## Release measurements

Live GNOME 50 smoke should record both latency and call count:

- cold first RemoteDesktop consent;
- cold first ScreenCast consent;
- restored-session cold capture;
- warm broker p50/p95 capture latency;
- known-target Cua state latency;
- semantic background action latency;
- exact foreground escalation latency;
- pixel-only target action latency;
- model/tool boundaries for representative known-target, ambiguous-target, and
  recovery tasks.

The north-star benchmark is simple: **how few decisions and calls does the agent
need to finish the task correctly?**
