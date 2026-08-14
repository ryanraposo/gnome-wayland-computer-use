# Determinism contract

GWCU exists to spend model calls on decisions, not mechanics.

## 1. Cua is the control authority

Cua Driver owns desktop targeting, geometry, activation, pointer/keyboard
delivery, verification, effects and refusals.

Never create a shadow control plane with `ydotool`, `/dev/uinput`, guessed
focus, or a project RDP/VNC server.

Never answer a Cua refusal with raw pointer/keyboard injection.

Never retry the same failed delivery shape blindly.

## 2. WORLDLINE owns transient truth

WORLDLINE maintains revisioned, session-scoped facts and predicates.

Facts are **valid until invalidated**. An action or event invalidates the
dependency paths it can affect; unrelated facts remain usable.

WORLDLINE is read-only. It does not become an alternate actuator.

## 3. Observation is an interrupt

Do not perform `observe → model → act → observe` ceremonially.

A new model-visible observation is justified only when fresh state can change
the next action and local predicates/oracles cannot establish that state.

Expected postconditions should be evaluated locally.

## 4. Direct truth beats visual inference

Prefer:

```text
AT-SPI event
filesystem event
process state
D-Bus property
gsettings value
network state
task-specific watcher
```

before interpreting pixels.

Use ScreenCast/PipeWire when the task is genuinely visual or cheaper evidence is
insufficient.

## 5. Determined action spans cross once

When two or more consecutive Cua actions are completely determined by the same
evidence, execute them behind one model/tool boundary.

A span stops at the first real boundary:

- returned state can change the next action;
- target identity became stale;
- a branch was not declared;
- an asynchronous transition lacks a sufficient completion predicate;
- Cua fails/refuses;
- user authorization or choice is required.

No fixed sleep or ritual screenshot belongs between already-decided actions.

## 6. Predicates are postconditions

A transaction should say what must become true.

```text
act
→ WORLDLINE revision
→ predicate true
→ continue
```

If a declared expectation cannot be established, surface the conflict instead
of manufacturing certainty.

## 7. `.gwcu` is durable truth only

`.gwcu` stores low-churn repo/workspace facts that are valuable on later runs.

WORLDLINE state never belongs in `.gwcu`.

Persistent machine/user truth never belongs in AGENTS.md.

Screenshots, documents, task history, transient focus, secrets and raw health
payloads are not durable truth.

## 8. One call owns local fan-out

If a deterministic local script can answer a question, call the script once.

Examples:

```text
profile.sh route
profile.sh recover
worldline-capture.sh
action span
```

Do not make the model manually perform the script's internal steps.

## 9. Contradiction beats cache

`.gwcu` accelerates routing; it is not control authority.

Live Cua state and current WORLDLINE evidence win when durable truth
contradicts reality.

## 10. Consent stays explicit

GNOME Wayland is the intended session. No X11 or XWayland session is required.

Cua's local pointer/keyboard path is:

```text
GNOME RemoteDesktop portal → EIS → libei
```

Whole-screen visual observation is independently authorized through
ScreenCast/PipeWire.

## 11. Installation is deterministic

The installer must:

- detect/qualify Ubuntu 26.04 GNOME Wayland;
- pin Cua instead of using `latest`;
- repair explicit portal/PipeWire/AT-SPI dependencies;
- establish RemoteDesktop consent;
- install WORLDLINE and observer lifecycle;
- preserve host-owned packages on teardown;
- prove Cua/runtime health before declaring readiness.

The uninstaller must reverse only GWCU-owned integration and preserve
repo/workspace `.gwcu` content.
