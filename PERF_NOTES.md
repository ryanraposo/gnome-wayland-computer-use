# Performance Notes

Performance is measured in **agent round-trips and repeated work**, not only
milliseconds.

## First-use call budget

| Situation | GWCU calls before first useful Cua state |
|---|---:|
| known app/window | **0** |
| uncertain installed/PWA identity | **1** — `profile.sh route` |
| host/runtime contradiction | **1** — `profile.sh recover` |
| explicit whole-screen request | **1** — `observe.sh` |

## `.gwcu` effect

Managed truth does not claim to cut an entire task by 100%. A warm exact app hit
eliminates **100% of the repeated launcher/PWA identity-resolution stage inside
the route call**.

Cold:

```text
route call
→ resolve scope
→ .gwcu miss
→ launcher/PWA resolution
→ Git scope: ensure /.gwcu is ignored
→ write stable identity
→ Cua
```

Warm:

```text
route call
→ nearest .gwcu
→ exact identity hit
→ no resolver
→ no rewrite
→ Cua
```

The route call itself remains one outer call. What disappears is repeated local
mechanical discovery and the model deliberation that would otherwise surround
it.

With persistence disabled:

```text
route call → identity resolver → Cua
route call → identity resolver → Cua
route call → identity resolver → Cua
```

With persistence enabled:

```text
route call → identity resolver → write .gwcu → Cua
route call → .gwcu hit → Cua
route call → .gwcu hit → Cua
```

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

## Non-Git workspaces

Nearest-existing `.gwcu` scope discovery means a general workspace can pay the
cold discovery cost once for all descendants. A structure such as
`~/.gwcw/.gwcu` avoids creating unrelated truth files in every scratch
subdirectory.

## One-time work is amortized in installation

The installer handles interactions that should not consume later task turns:
managed-truth preference, GNOME RemoteDesktop authorization, Hermes slash
command registration, native dependency repair, observer setup, and readiness
proof. Exact qualified Cua and an existing RemoteDesktop restore token skip
their corresponding repeated setup.

## Whole-screen capture

The private socket is cheap; the broker starts on demand; one portal session and
PipeWire remote stay warm for a bounded task burst; idle expiry releases them.
The direct fallback is Screenshot-portal-only.

## Release measurements

Live GNOME 50 smoke should record:

- fresh installer consent path and repeat-install path;
- cold first RemoteDesktop consent;
- cold first ScreenCast consent;
- warm broker p50/p95 capture latency;
- known-target Cua state latency;
- `.gwcu` cold route and warm route latency;
- identity-resolver invocation count across cold/warm runs;
- non-Git ancestor-scope lookup latency;
- semantic background action latency;
- exact foreground escalation latency;
- pixel-only target action latency;
- model/tool boundaries for representative known, ambiguous, and recovery tasks.

The north-star benchmark is simple: **how few decisions and calls does the agent
need to finish the task correctly?**
