# Determinism

The model should decide **intent**, not desktop mechanics.

## Rule 1: one control authority

Cua Driver owns the control state machine.

```text
intent → Cua state → Cua action → Cua verdict
```

Project scripts do not compete with Cua for semantics, geometry, activation,
input, verification, or refusal policy.

## Rule 2: observation answers only observation

GWCU's ScreenCast/PipeWire broker provides whole-screen evidence. It never
becomes a second computer-control backend.

## Rule 3: machine truth is literal

`gwcu.diagnose.v2` uses top-level `ok=true` only when the current session is
actually ready. Cua readiness comes from Cua's stable `health_report`
`structuredContent`; `cua-health.py` transports that report rather than
reconstructing it. `cua-driver doctor --json` is supplemental detail.

## Rule 4: scripts compose hard sequences

A local subprocess is cheap. A model/tool boundary is expensive.

```text
unknown target
→ profile.sh route --machine NAME
  → project AGENTS truth lookup
  → app-identity.sh only on miss
  → stable identity write-back on confident resolution
  → gwcu.route.v1

host contradiction
→ profile.sh recover --machine
  → cached profile read
  → refresh only if stale/missing
     → diagnose.sh
        → Cua health + GNOME observation facts
  → gwcu.route.v1
```

The agent sees one structured result, not the helper fan-out.

## Rule 5: project memory contains invariants, not history

The project-root `AGENTS.md` managed block is a bounded acceleration cache.
Records are one-line `gwcu:app:v1` compact JSON beneath exact start/end markers.

Allowed facts are low-churn routing identity: display name, desktop ID, app ID,
StartupWMClass, and app kind. No timestamps, screenshots, health state, task
history, user text, or window coordinates belong there.

The route script reads this cache before launcher scanning and updates it only on
a confident deterministic resolution. User AGENTS content outside the markers is
untouchable. Live Cua state always outranks remembered identity.

## Rule 6: remove ritual from the hot path

A known target triggers **zero GWCU setup calls** before Cua.

It should not trigger update checks, broad diagnostics, app/window enumeration,
whole-screen capture, toolkit classification, fallback speculation, or blind
retries.

```text
one target state → useful actions → verification at a real decision boundary
```

## Rule 7: use native orchestration by kind of work

When Hermes exposes its orchestration tools:

```text
stable recurring mechanics → repository script
one-off mechanical fan-out → execute_code
independent reasoning       → delegate_task
bounded long process        → terminal background + notify_on_complete
real user choice            → clarify
interactive desktop action  → parent Cua loop
```

Do not delegate work that may need user clarification or portal consent.

## Rule 8: refusals are information

If Cua says a delivery shape is unsafe or unavailable, the agent may choose a
genuinely different supported Cua route or report the limitation. It must not
inject raw input into the currently focused application.

## Rule 9: installation is a deterministic program

There is one installer source. It verifies first, repairs only missing Ubuntu
foundation, provisions Cua through upstream-supported paths, enables the
observer, and validates the finished system against Cua's own stable health
contract. Runtime patching of a second installer is forbidden.