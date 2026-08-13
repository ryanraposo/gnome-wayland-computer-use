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

## Rule 5: consecutive determined actions are one call

If two or more consecutive Cua actions are fully determined by the same current
evidence, they **MUST cross the model/tool boundary exactly once**.

```text
WRONG
click → model → type → model → Enter

RIGHT
model decides click → type → Enter
  → ONE computer-use.sh span invocation
      → Cua click
      → Cua type_text
      → Cua key_press
  → model only at the next real decision boundary
```

A successful action does not justify model re-entry. Split a span only when its
result can change the remaining action/arguments, grounding becomes stale, a
real async transition needs fresh evidence, Cua fails/refuses, or new user
authorization/choice is required.

The installed span executor keeps one Cua MCP session open and performs the
already-decided Cua operations internally. This guarantees one **outer**
model-visible invocation; it does not claim an atomic native Cua batch RPC.

The executor fails closed at the first Cua failure/refusal/transport boundary.
No later queued action may execute after that boundary.

## Rule 6: persistent local truth has one surface

Persistent machine/workspace truth belongs in `.gwcu`, not `AGENTS.md`, prompt
prose, task logs, or scattered cache files.

Scope resolution:

```text
explicit GWCU_SCOPE_ROOT
→ Git worktree root, when inside Git
→ nearest existing ancestor .gwcu, outside Git
→ current workdir
```

A Git repository always owns its own root truth file, even beneath a broader
non-Git workspace. Outside Git, an existing ancestor `.gwcu` may define a
long-lived general workspace.

For Git scopes, managed persistence must establish `/.gwcu` in the root
`.gitignore` before the first truth write. If safe ignore setup fails, the write
fails.

## Rule 7: truth classes have different ownership

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

## Rule 8: one-time setup belongs in installation

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

## Rule 9: remove ritual from the hot path

A known target triggers **zero GWCU setup calls** before Cua.

It does not trigger update checks, broad diagnostics, app/window enumeration,
whole-screen capture, toolkit classification, fallback speculation, model
re-entry between already-decided actions, or blind retries.

```text
one target state → ONE deterministic action-span call → real decision boundary
```

## Rule 10: use Hermes primitives by job shape

```text
stable recurring mechanics → repository script
one-off mechanical fan-out → execute_code
independent reasoning       → delegate_task
bounded long process        → terminal background + notify_on_complete
real user choice            → clarify
interactive desktop action  → parent Cua loop
```

Portal consent and interactive desktop decisions stay in the parent session.

## Rule 11: refusals are information

If Cua says a delivery shape is unavailable, choose a genuinely different
supported Cua route or report the limitation. Do not inject raw input into the
currently focused application.

## Rule 12: installation is a deterministic program

There is one installer source. It verifies first, repairs only missing Ubuntu
foundation, provisions through upstream-supported paths, and validates the
finished system. Runtime patching of a second installer is forbidden.
