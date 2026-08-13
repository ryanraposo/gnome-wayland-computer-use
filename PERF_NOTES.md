# Performance Notes

Performance is measured in **agent round-trips**, not only milliseconds.

## First-use call budget

| Situation | GWCU calls before first useful Cua state |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen request | **1** — `observe.sh` |

## Stable-memory effect

Managed project truths do not claim to cut an entire task by 100%. They can
eliminate **100% of the repeat identity-routing setup call** when a stable exact
identity is already present in the current project's managed `AGENTS.md` block.

Cold:

```text
route call → project miss → launcher resolution → write stable truth → Cua
```

Warm:

```text
route call → project hit → Cua
```

The route call itself remains one outer call; the saved work is the repeated
identity-resolution stage inside it.

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

## One-time work is amortized in installation

The installer handles interactions that should not consume later task turns:
managed-memory preference, GNOME RemoteDesktop authorization, Hermes slash
command registration, native dependency repair, observer setup, and readiness
proof. Exact qualified Cua and an existing RemoteDesktop restore token skip
their corresponding repeated setup.

## Whole-screen capture

The private socket is cheap; the broker starts on demand; one portal session and
PipeWire remote stay warm for a bounded task burst; idle expiry releases them.
The direct fallback is Screenshot-portal-only.

## Release measurements

Live GNOME 50 smoke should record:

- installer one-time consent path and repeat-install path;
- cold first RemoteDesktop consent;
- cold first ScreenCast consent;
- warm broker p50/p95 capture latency;
- known-target Cua state latency;
- cold and warm managed identity routing;
- semantic background action latency;
- exact foreground escalation latency;
- pixel-only target action latency;
- model/tool boundaries for representative known, ambiguous, and recovery tasks.

The north-star benchmark is simple: **how few decisions and calls does the agent
need to finish the task correctly?**
