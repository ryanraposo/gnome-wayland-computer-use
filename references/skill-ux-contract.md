# Skill UX contract

This reference describes how the computer-use skill should feel to an agent.

## Phase transitions

```text
intent
→ ground current state
→ choose deterministic span / local predicate
→ Cua acts
→ WORLDLINE revises
→ continue locally while declared conditions hold
→ model re-enters at a real decision boundary
→ prove requested outcome
```

A phase transition is justified when fresh state can change the next decision,
not merely because an action occurred.

## Latency budget and decision boundaries

Optimize model boundaries before local milliseconds.

Known grounded targets should require zero setup calls before useful work.
Unknown app/PWA identity may spend one local route call. Host contradictions
may spend one recovery call. Whole-screen visual observation should be a single
escalation call only when cheaper evidence cannot answer the task.

Two or more fully determined consecutive Cua actions belong behind one outer
model/tool call.

WORLDLINE revisions are cheap local bookkeeping. The performance goal is many
useful revisions and actions per model re-entry.

## Authority

Cua Driver is the sole desktop actuator.

WORLDLINE is read-only current-state machinery. `.gwcu` is durable truth.
Neither may become an alternate pointer/keyboard control path.

A Cua refusal is evidence. Never bypass it with raw input injection.

## Assumptions

Use a fact without re-checking when:

- it is durable `.gwcu` truth and current evidence does not contradict it; or
- it is a current WORLDLINE fact whose dependency has not been invalidated.

When a declared dependency is invalidated, reacquire only what the next action
needs.

## Question budget

Ask the user only for genuine preference/authorization decisions that local
state cannot answer.

Do not ask a human to resolve deterministic host discovery, app identity,
postcondition checks or known runtime state.

## Decision ownership

The model owns intent and undeclared branches.

Local deterministic machinery owns:

- routing fan-out;
- action spans whose arguments are already known;
- revision/invalidation bookkeeping;
- predicate evaluation;
- direct-oracle collection;
- retry/backoff that does not require a new strategy.

## Progress surface

Expose meaningful boundaries:

```text
target resolved
action span started/completed
WORLDLINE postcondition satisfied
portal consent required
Cua refusal/conflict
task complete
```

Avoid narrating every click or internal revision.

## Mutation contract

Before mutating the desktop:

- target state must be sufficiently grounded;
- action arguments must be determined;
- a known refusal must not be bypassed.

For multi-action spans, stop when remaining actions are no longer justified by
the evidence that admitted the span.

## Completion proof obligations

Use the cheapest sufficient proof:

```text
direct oracle / WORLDLINE predicate
→ Cua verification
→ targeted semantic evidence
→ visual evidence
```

Do not add a screenshot solely as ritual confirmation.

If evidence remains ambiguous after the appropriate escalation, report the
conflict instead of inventing success.
