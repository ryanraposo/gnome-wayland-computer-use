# Performance notes

GWCU optimizes **model boundaries first**, then local latency.

A 20 ms local optimization is useful. Eliminating a full model/tool round-trip
is usually more useful.

## The expensive loop

Naive desktop automation:

```text
observe
→ model
→ act
→ observe
→ model
→ act
```

The main cost is repeated serialization, inference and tool orchestration around
state transitions that can often be verified locally.

## Savings hierarchy

### 1. Keep determined actions inside one call

If click, type and Enter are already determined, `computer-use.sh span` keeps
one Cua MCP process/session open for the sequence.

```text
3 model-visible calls → 1 model-visible call
```

### 2. Wait on predicates instead of screenshots

WORLDLINE can wait for:

```text
filesystem/process/task event
gsettings/network state
AT-SPI mutation
declared direct fact
```

and wake work when the postcondition becomes true.

```text
act → observe → model → continue
```

becomes:

```text
act → WORLDLINE predicate → continue
```

### 3. Preserve unaffected knowledge

Valid-until-invalidated facts prevent unrelated UI activity from forcing a
whole-state rediscovery.

### 4. Route stable identity locally

`.gwcu` can skip repeated launcher/PWA resolution. `profile.sh route` owns the
miss path in one call.

### 5. Keep visual capture warm and optional

The observer is socket activated and can keep ScreenCast/PipeWire warm across a
short visual burst. WORLDLINE asks for a fresh frame only when a transaction
needs visual evidence.

## What to measure

Useful benchmark counters are:

```text
model-visible tool calls / task
model re-entries / task
Cua actions / model-visible call
WORLDLINE revisions / task
predicates satisfied locally / task
visual captures / task
conflicts returned to model / task
route cache hit rate
```

The target is not “few revisions.” Revisions are cheap local bookkeeping.

The target is:

> **many mechanically useful revisions per model re-entry.**

## Latency discipline

Avoid:

- fixed sleeps;
- repeated host preflights;
- full-screen capture after every action;
- separate model calls for deterministic routing fan-out;
- restarting Cua or ScreenCast infrastructure inside a span;
- re-reading durable truth that is already in the current execution context.

Prefer:

- event-driven completion;
- bounded local timeouts;
- one Cua MCP session per span;
- socket-activated persistent sensors;
- direct oracles;
- regional/visual escalation only after cheaper evidence is insufficient.

## Benchmark truthfulness

Do not claim a theoretical model-call reduction as measured performance.

For each scenario, record:

```text
initial knowledge
actions issued
WORLDLINE revisions
local predicates
visual captures
model-visible calls
conflicts/escalations
elapsed wall time
```

That makes the speed advantage attributable instead of theatrical.
