# Determinism

The model should decide **intent**, not desktop mechanics.

## Rule 1: one control authority

Cua Driver owns the control state machine.

```text
intent → Cua state → Cua action → Cua verdict
```

GWCU programs do not compete with Cua for semantics, geometry, activation,
input, verification, or refusal policy.

## Rule 2: observation answers only observation

GWCU's ScreenCast/PipeWire broker provides whole-screen evidence. It never
becomes a second computer-control backend.

## Rule 3: machine truth is literal

`gwcu.diagnose.v2` uses top-level `ok=true` only when the current session is
actually ready. Cua readiness comes from Cua's stable `health_report`; doctor
output is supplemental detail.

## Rule 4: scripts compose scripts

A local subprocess is cheap. A model/tool boundary is expensive.

```text
uncertain target
→ profile.sh route
  → .gwcu lookup
  → identity resolver only on miss
  → stable write-back only when managed + exact
  → gwcu.route.v1

host contradiction
→ profile.sh recover
  → cached profile
  → refresh only if stale/missing
     → diagnose.sh
  → gwcu.route.v1
```

`route` never wakes diagnostics merely because target identity is uncertain.
`recover` is the deliberate expensive path but still costs one outer agent call.

## Rule 5: persistent local truth has one surface

Persistent machine/workspace truth belongs in `.gwcu`, not `AGENTS.md`, prompt
prose, task logs, or scattered cache files.

Scope resolution:

```text
explicit GWCU_SCOPE_ROOT
→ nearest existing ancestor .gwcu
→ Git root
→ current workdir
```

This supports both repositories and non-Git workspaces.

For Git scopes, managed persistence must establish `/.gwcu` in the root
`.gitignore` before the first truth write. If safe ignore setup fails, the write
fails.

## Rule 6: truth classes have different ownership

`.gwcu` uses schema `gwcu.truths.v1` and separates:

- `observed`: generated low-churn environment facts;
- `capabilities`: generated compact capability conclusions;
- `calibration`: generated learned mappings/measurements;
- `preferences`: user-authored choices, preserved on regeneration;
- `apps`: generated stable launcher/PWA identity.

Generated sections store conclusions, not transcripts. They may be regenerated.
Preferences and unknown top-level extension keys are preserved.

Never store screenshots, user text, task/conversation history, secrets,
clipboard content, raw health dumps, transient focus, or transient geometry.

**Live Cua state always wins on contradiction.**

## Rule 7: one-time setup belongs in installation

The installer owns one-time machine/user setup:

- Ubuntu foundation repair;
- qualified Cua installation;
- Cua GNOME helper installation;
- managed-`.gwcu` preference;
- RemoteDesktop/EIS control authorization;
- Hermes `/computer-use` plugin registration when Hermes is present;
- observer installation;
- health proof and ownership bookkeeping.

`.gwcu` itself is scope-local and created lazily where durable work happens.

## Rule 8: remove ritual from the hot path

A known target triggers **zero GWCU setup calls** before Cua.

It does not trigger update checks, broad diagnostics, app/window enumeration,
whole-screen capture, toolkit classification, fallback speculation, or blind
retries.

```text
one target state → useful actions → verification at a real decision boundary
```

## Rule 9: use Hermes primitives by job shape

```text
stable recurring mechanics → repository script
one-off mechanical fan-out → execute_code
independent reasoning       → delegate_task
bounded long process        → terminal background + notify_on_complete
real user choice            → clarify
interactive desktop action  → parent Cua loop
```

Portal consent and interactive desktop decisions stay in the parent session.

## Rule 10: refusals are information

If Cua says a delivery shape is unavailable, choose a genuinely different
supported Cua route or report the limitation. Do not inject raw input into the
currently focused application.

## Rule 11: installation is a deterministic program

There is one installer source. It verifies first, repairs only missing Ubuntu
foundation, provisions through upstream-supported paths, and validates the
finished system. Runtime patching of a second installer is forbidden.
