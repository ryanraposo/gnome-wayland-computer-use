# Performance Notes

Performance is measured in **agent round-trips**, not only milliseconds.

## First-use call budget

| Situation | GWCU calls before first useful Cua state |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen request | **1** — `observe.sh` |

The optimization is structural: many local script/process calls can occur inside
one terminal invocation without becoming many model/tool turns.

## Fast path

```text
known target
→ one Cua target/window state
→ AX or PX from that state
→ deterministic action span
→ verify only when the next decision depends on it
```

No diagnostics, update checks, launcher scans, or whole-screen captures belong
on that path.

## Project-memory fast path

`profile.sh route` now has a two-level identity cache:

```text
project AGENTS managed truth
→ launcher/PWA scan only on miss
→ write back stable identity only on confident resolution
```

A hit replaces a launcher scan with parsing a tiny bounded block. The block has
no timestamps, so successful repeated use produces no file churn. It stores
only fields likely to remain true across sessions and reboots. Live Cua state is
the invalidation signal when remembered identity stops matching reality.

## Script-script composition

- `route NAME` combines project memory, cached host context, and deterministic
  identity resolution inside one outer call. Missing launcher metadata is not
  treated as a missing live window.
- `recover` is reserved for host contradiction and collapses cached read →
  refresh-if-needed → diagnose inside one outer call.

This converts recurring branching deliberation into compact `gwcu.route.v1`
information.

## Hermes orchestration savings

Hermes can remove additional boundaries when work fits its native primitives:

- `clarify`: one structured user decision instead of prose/options/reparse;
- `execute_code`: many mechanical terminal/file/web calls and intermediate
  results inside one model turn;
- `delegate_task`: independent reasoning/context work without polluting the
  parent's working context;
- terminal `background=true, notify_on_complete=true`: bounded long processes
  complete without polling turns.

These mechanisms complement GWCU scripts. Repeated computer-use mechanics stay
versioned and tested in the repository; one-off task composition belongs in the
agent runtime.

## Whole-screen capture

Whole-screen observation remains separate and lazy:

- the systemd socket is cheap;
- the broker starts only on a capture request;
- one portal session and PipeWire remote stay warm for a bounded task burst;
- each request asks for a fresh frame without rebuilding the capture chain;
- idle expiry releases the stream.

The direct `capture.sh` path remains a Screenshot-portal-only fallback.

## Avoided costs

- no `ydotoold` startup;
- no uinput permission probing;
- no custom Cua daemon lifecycle;
- no duplicated AT-SPI or WinRects investigation;
- no toolkit-driven focus deliberation;
- no model-invented fallback ladder;
- no model-driven `profile read → refresh → diagnose` chain;
- no repeat launcher scan after a stable project-memory hit.

## Release measurements

Live GNOME 50 smoke should record both latency and call count:

- cold first RemoteDesktop consent;
- cold first ScreenCast consent;
- restored-session cold capture;
- warm broker p50/p95 capture latency;
- cold route vs project-memory-hit route latency;
- known-target Cua state latency;
- semantic background action latency;
- exact foreground escalation latency;
- pixel-only target action latency;
- model/tool boundaries for representative known-target, ambiguous-target,
  recovery, clarification, delegation, and bounded-background tasks.

The north-star benchmark is simple: **how few decisions and calls does the agent
need to finish the task correctly?**