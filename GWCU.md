# `.gwcu` local truth contract

`.gwcu` is GWCU's repo/workspace-local truth file. It exists so an agent can
turn an observation into durable information once, then avoid rediscovering the
same machine/workspace facts on every task.

It is deliberately **not** an agent prompt, task log, history file, or control
authority.

## Location and scope

Scope resolution is deterministic:

```text
GWCU_SCOPE_ROOT override
        ↓ absent
Git worktree root, when inside Git
        ↓ not in Git
nearest ancestor containing .gwcu
        ↓ absent
current GWCU working directory
```

A Git repository is always isolated to its own root. If a repo lives inside a
broader non-Git workspace that already has `.gwcu`, the repo still gets its own
`.gwcu`; parent workspace truth never bleeds into the repository.

Outside Git, the nearest-existing rule makes durable general workspaces
first-class. For example:

```text
~/.gwcw/
├── .gwcu
├── scratch/
├── experiments/
└── repos/
    └── my-project/       # Git repo: uses my-project/.gwcu, not ~/.gwcw/.gwcu
```

An agent working under `~/.gwcw/scratch/` reuses `~/.gwcw/.gwcu`. An agent
working in the nested Git repo uses that repository's root `.gwcu`.

When managed truth is enabled in a Git worktree, GWCU must ensure the root
`.gitignore` contains:

```gitignore
# GWCU local machine/workspace truths
/.gwcu
```

**before** it creates or writes `.gwcu`. If that ignore rule cannot be safely
established, GWCU refuses the persistent write instead of risking a committed
machine-state file.

Non-Git workspaces need no `.gitignore` ceremony.

## Encoding

`.gwcu` is canonical, pretty-printed JSON with the schema identifier:

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

Why JSON:

- every agent/runtime can parse it without another package;
- humans can inspect/edit it directly;
- atomic deterministic rewrites are straightforward;
- unknown top-level extension keys can be preserved;
- schema versioning is explicit instead of inferred from comments or filenames.

The `.gwcu` filename is the convention. `gwcu.truths.v1` is the format contract.

## Truth classes

### `observed`

Low-churn facts that GWCU directly observed about the current environment.
Examples:

```json
{
  "desktop": "GNOME",
  "session_type": "wayland"
}
```

GWCU may regenerate these values from fresh evidence.

### `capabilities`

What this scope/machine can currently do, expressed as compact facts rather than
raw diagnostic transcripts.

```json
{
  "cua_control": true,
  "gnome_wayland": true,
  "whole_screen": true
}
```

Capabilities are generated truth and may be regenerated.

### `calibration`

Stable measurements or mappings learned through explicit calibration. Examples
include coordinate-space conventions, a preferred display identity, or a
measured transform needed by a deterministic local program.

Calibration is generated truth. It may be discarded and rebuilt when the
underlying device/display topology changes.

### `preferences`

User-authored operating preferences that affect how GWCU should behave but are
not observations about the machine.

```json
{
  "preserve_foreground": true
}
```

GWCU preserves this section when generated truth is regenerated. Tools may add
preference keys only when the user has expressed the preference or explicitly
asked the tool to store it.

### `apps`

Stable target identity learned from deterministic launcher/PWA resolution.
Entries are keyed by their most stable available identity:

```json
{
  "chatgpt.desktop": {
    "app_id": "chatgpt_app",
    "desktop_id": "chatgpt.desktop",
    "key": "chatgpt.desktop",
    "kind": "installed-web-app",
    "name": "ChatGPT",
    "source": "launcher",
    "startup_wm_class": "crx_chatgpt_app"
  }
}
```

A warm exact hit lets `profile.sh route` skip launcher/PWA resolution. Live Cua
state still wins if the running desktop contradicts the stored identity.

## What never belongs here

`.gwcu` must not become a disguised event stream. Do not persist:

- screenshots or image data;
- user-entered text or document contents;
- task history or conversation history;
- timestamps whose only purpose is to record activity;
- transient focus state;
- transient window coordinates/geometry;
- raw health/doctor dumps;
- secrets, tokens, credentials, or clipboard contents.

A generated section should contain the **conclusion** produced by observation,
not the observation transcript itself.

## Regeneration and extension

`observed`, `capabilities`, `calibration`, and `apps` are generated sections.
They can be cleared and regenerated while preserving `preferences` and unknown
top-level extension keys.

```bash
profile.sh truths regenerate --machine
```

Other tools may adopt `.gwcu` by:

1. recognizing `schema: gwcu.truths.v1`;
2. reading the standard sections above;
3. preserving unknown top-level keys;
4. putting namespaced extensions in their own top-level object;
5. treating live evidence as higher authority than stored generated truth.

## The performance contract

The point of `.gwcu` is not memory for memory's sake. It is to remove repeated
reasoning from the hot path:

```text
first encounter
agent uncertainty
  → [TOOL] profile.sh route
      → .gwcu miss
      → local identity resolver
      → exact identity
      → write .gwcu
  ← compact gwcu.route.v1
  → [CUA] useful target state/action

repeat encounter
agent uncertainty
  → [TOOL] profile.sh route
      → .gwcu hit
      → no identity scan
      → no project-file reasoning
      → no diagnostics
  ← compact gwcu.route.v1
  → [CUA] useful target state/action
```

Stored truth removes repeated mechanical work **inside** the one route call. A
known target still pays zero GWCU setup calls and goes straight to Cua.
