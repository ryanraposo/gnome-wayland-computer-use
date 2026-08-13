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

The recovery vocabulary stays small:

```text
logout_login
start_gnome_wayland_session
rerun_installer
inspect_cua_health
refresh_profile
```

## Rule 4: scripts compose scripts

A local subprocess is cheap. A model/tool boundary is expensive.

The agent should not fan out through helpers when a deterministic wrapper can
compose them in one shell invocation:

```text
unknown target
→ profile.sh route --machine NAME
  → cached profile read
  → app-identity.sh resolve
  → gwcu.route.v1

host contradiction
→ profile.sh recover --machine
  → cached profile read
  → refresh only if stale/missing
     → diagnose.sh
        → Cua health + GNOME observation facts
  → gwcu.route.v1
```

`route` never refreshes diagnostics merely because target identity is uncertain.
`recover` is explicitly the expensive path and collapses `read → refresh →
diagnose` into one agent call.

## Rule 5: remove ritual from the hot path

A known target should trigger **zero GWCU setup calls** before Cua.

It should not trigger:

- update checks;
- broad diagnostics;
- app/window enumeration;
- whole-screen capture;
- toolkit classification;
- fallback speculation;
- blind retries.

The desired span is:

```text
one target state → useful actions → verification at a real decision boundary
```

## Rule 6: refusals are information

If Cua says a delivery shape is unsafe or unavailable, the agent may choose a
genuinely different supported Cua route or report the limitation. It must not
inject raw input into the currently focused application.

## Rule 7: installation is a deterministic program

There is one installer source. It verifies first, repairs only missing Ubuntu
foundation, provisions Cua through upstream-supported paths, enables the
observer, and validates the finished system against Cua's own stable health
contract. Runtime patching of a second installer is forbidden.
