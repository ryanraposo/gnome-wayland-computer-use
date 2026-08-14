# `.gwcu` truth contract

`.gwcu` is GWCU's durable local truth file.

It answers:

> What low-churn fact is worth knowing again the next time an agent works in
> this repo or workspace?

WORLDLINE is transient session state; `.gwcu` is deliberately **not** WORLDLINE state.

```text
WORLDLINE   current session / revisions / predicates / invalidation
.gwcu       durable repo/workspace facts worth reusing later
Cua         live desktop control authority
```

## Scope

Resolution is deterministic:

```text
GWCU_SCOPE_ROOT override
→ Git worktree root
→ nearest non-Git ancestor already containing .gwcu
→ current working directory
```

A Git repository always owns its own truth file. A repo nested inside a broader
workspace does not inherit that workspace's `.gwcu`.

Outside Git, descendants may share the nearest ancestor `.gwcu`.

## Git safety

When managed truth is enabled in a Git worktree, GWCU first ensures the root
`.gitignore` contains:

```gitignore
/.gwcu
```

Only then may it create or update `.gwcu`.

If that protection cannot be established safely, the persistent write fails.

## Schema

`.gwcu` is canonical JSON:

```json
{
  "apps": {},
  "calibration": {},
  "capabilities": {},
  "observed": {},
  "preferences": {},
  "schema": "gwcu.truths.v1"
}
```

### `apps`

Stable launcher/PWA identity and routing facts.

Examples:

```text
desktop file ID
stable app ID
browser-backed application identity
```

### `calibration`

Stable learned measurements or mappings that materially reduce later work.

### `capabilities`

Compact conclusions about reusable machine/workspace capability.

### `observed`

Low-churn facts directly observed from the environment.

### `preferences`

User-authored behavior preferences. Generated refreshes preserve this section.

## What does not belong here

Never persist:

- screenshots or frame hashes;
- WORLDLINE revisions or predicates;
- transient focus/window geometry;
- documents, prompts or user text;
- task/conversation history;
- credentials, tokens or clipboard contents;
- raw diagnostic/health payloads;
- facts whose lifetime is shorter than the workspace value they provide.

A useful test:

> Will this fact still save meaningful work in a later session, and is it safe
> to keep locally?

If not, leave it in WORLDLINE/runtime state or do not persist it.

## Managed mode

The installer asks once whether GWCU may manage `.gwcu` truth.

At runtime:

```bash
/computer-use managed on
/computer-use managed off
/computer-use managed status
/computer-use truths
```

Environment override:

```bash
GWCU_TRUTHS=off
```

Managed mode owns the `.gwcu` machinery, not the workspace data itself.
Uninstall therefore preserves repo/workspace `.gwcu` files and their
`.gitignore` protection.

## Contradictions

`.gwcu` accelerates discovery. It is never authoritative over reality.

```text
stored identity
    ↓
use directly when compatible
    ↓
live Cua/WORLDLINE contradiction
    ↓
live state wins
    ↓
stable correction may be written back
```

This keeps durable truth useful without turning it into stale prompt dogma.
