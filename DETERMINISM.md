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

## Rule 4: scripts compose scripts

A local subprocess is cheap. A model/tool boundary is expensive.

```text
uncertain target
→ profile.sh route
  → managed project truth
  → identity resolver only on miss
  → stable write-back only when allowed
  → gwcu.route.v1

host contradiction
→ profile.sh recover
  → cached profile
  → refresh only if stale/missing
     → diagnose.sh
  → gwcu.route.v1
```

`route` never refreshes diagnostics merely because target identity is uncertain.
`recover` is the deliberate expensive path but still costs one outer agent call.

## Rule 5: stable truths may persist; transient state may not

Managed `AGENTS.md` blocks are bounded acceleration caches.

Eligible: display name, desktop ID, app ID, `StartupWMClass`, app kind.

Forbidden: screenshots, user text, timestamps, health snapshots, task history,
window geometry, coordinates, focus state, or other transient task state.

Live Cua state always wins on contradiction. `GWCU_PROJECT_MEMORY=off` is the
runtime override, and the installer's persistent preference is user-controlled.

## Rule 6: one-time setup belongs in installation

The installer owns one-time machine/user setup:

- Ubuntu foundation repair;
- qualified Cua installation;
- Cua GNOME helper installation;
- managed-AGENTS preference;
- RemoteDesktop/EIS control authorization;
- Hermes `/computer-use` plugin registration when Hermes is present;
- observer installation;
- health proof and ownership bookkeeping.

A rerun skips already-qualified Cua and already-established RemoteDesktop consent
where the recorded local state proves they are already done.

## Rule 7: remove ritual from the hot path

A known target should trigger **zero GWCU setup calls** before Cua.

It should not trigger update checks, broad diagnostics, app/window enumeration,
whole-screen capture, toolkit classification, fallback speculation, or blind
retries.

```text
one target state → useful actions → verification at a real decision boundary
```

## Rule 8: use Hermes primitives by job shape

```text
stable recurring mechanics → repository script
one-off mechanical fan-out → execute_code
independent reasoning       → delegate_task
bounded long process        → terminal background + notify_on_complete
real user choice            → clarify
interactive desktop action  → parent Cua loop
```

Portal consent and interactive desktop decisions stay in the parent session.

## Rule 9: refusals are information

If Cua says a delivery shape is unsafe or unavailable, the agent may choose a
genuinely different supported Cua route or report the limitation. It must not
inject raw input into the currently focused application.

## Rule 10: installation is a deterministic program

There is one installer source. It verifies first, repairs only missing Ubuntu
foundation, provisions through upstream-supported paths, and validates the
finished system. Runtime patching of a second installer is forbidden.
