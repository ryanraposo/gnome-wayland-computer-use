# Determinism

The model should decide **intent**, not desktop mechanics.

## Rule 1: one control authority

Cua Driver owns the control state machine. Project scripts must never compete
with it for semantics, geometry, activation, input, verification, or refusal
policy.

```text
intent → Cua state → Cua action → Cua verdict
```

The skill can choose among grounded semantic and visual actions, but it does not
re-derive how GNOME delivers them.

## Rule 2: observation answers only observation

The project's ScreenCast/PipeWire broker exists for whole-screen evidence. It
is independent from Cua so an explicit screen request does not require a Cua
window binding, but it does not become a second computer-control backend.

## Rule 3: machine truth is literal

`gwcu.diagnose.v2` uses top-level `ok=true` only when the current session is
actually ready. Cua health comes from `cua-driver doctor --json`; the project
adds only its own session/observation facts.

The deterministic next-action vocabulary stays small:

```text
logout_login
start_gnome_wayland_session
rerun_installer
run_cua_doctor
refresh_profile
```

## Rule 4: remove ritual from the hot path

A known target should not trigger:

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

## Rule 5: refusals are information

If Cua says a delivery shape is unsafe or unavailable, the agent may choose a
genuinely different supported Cua route or report the limitation. It must not
inject raw input into the currently focused application.

## Rule 6: installation is a deterministic program

There is one installer source. It verifies first, repairs only missing Ubuntu
foundation, provisions Cua through upstream-supported paths, enables the
observer, and validates the finished system. Runtime patching of a second
installer is forbidden.
