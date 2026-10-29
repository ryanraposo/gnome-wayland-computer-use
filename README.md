```text
                          ▄  ▄▄  ▄▄▄▄
                             ▄▀ 0x0 ▀▄
                              █  ───  █
                              █  ███  █
                               ▀▀   ▀▀
```

# gnome-wayland-computer-use

Agents have variable success using Linux. GWCU makes computer use dependable on Ubuntu 26 GNOME Wayland with exact target identity, local state, and verified outcomes.

**Cua acts. WORLDLINE knows. `.gwcu` remembers.**

```text
model decides → exact target → Cua acts → WORLDLINE revises truth
→ expected postcondition becomes true → continue locally
```

Observation is an interrupt, not a ritual RPC. Facts are valid until invalidated.

## What GWCU is

GWCU is best understood as an **agent skill with a small enforcement/runtime system around it**. `SKILL.md` is the canonical agent contract: routing, foreground behavior, acquisition, verification, browser continuity, failure boundaries, and the exact action semantics live there.

GWCU uses **Cua Driver's MCP/tool surface** for computer use; GWCU itself is not another MCP server. The runtime exists to make the skill's contract mechanical instead of advisory.

| Component | Role |
|---|---|
| **`SKILL.md`** | Canonical agent behavior contract and `/computer-use` task surface. |
| **Hermes policy plugin** | Wraps Hermes' built-in `computer_use` tool so saved delivery policy, ACQUIRE, exact foreground admission, and gateway identity are enforced. |
| **Cua Driver** | Upstream actuator and native/browser UI tool surface. All GWCU desktop GUI input goes through Cua. |
| **Cua GNOME helper** | Presents one exact `(pid, window_id)` and proves focused + visible state. |
| **GWCU local runtime** | Installer, doctor, action spans, presentation helpers, routing and lifecycle repair. |
| **WORLDLINE** | Transient revisioned state, invalidation, predicates, waits and conflicts. Read-only: it never injects input. |
| **`.gwcu`** | Durable low-churn machine/workspace truth such as stable identity, capabilities, calibration and preferences. |

GNOME Wayland uses the `Remote Desktop` portal → EIS/libei for compositor-approved local input. GWCU installs no RDP/VNC server or raw-input daemon. **No X11 or XWayland session is required.**

## Use it

```text
/computer-use <task>
/computer-use status
/computer-use trace
/computer-use present --pid PID --window-id ID
/computer-use list-windows [--on-screen-only] [--pid PID] [--json|--table|--raw]
/computer-use cursor-color [#RRGGBB]
/computer-use background [on|off|status]
/computer-use managed [on|off|status]
/computer-use truths
/computer-use consent
/computer-use doctor
/computer-use help
```

Examples: `/computer-use open YouTube and play something`, `/computer-use send the message I drafted`.

`/computer-use trace` shows the last redacted physical span plus the canonical path (`computer-use.sh span` stays internal-only). Detailed agent behavior belongs in `SKILL.md`.

## Agent routing

Choose the route from the state the task needs next:

```text
desktop/native-app state or visible result → Cua
user's current browser session             → Cua
web content, research, reading, retrieval  → browser/web tooling
shell or CLI state                         → terminal tool
terminal window as visible desktop UI      → Cua
```

A task can move between these naturally. Once work targets a specific browser window/session, its UI mutations remain on Cua so native window identity, tab/page state, visibility and completion evidence stay coherent.

## Hermes integration

```text
computer-use skill
      ↓
GWCU policy plugin
      ↓
Hermes built-in computer_use
      ↓
Cua Driver
```

GWCU replaces the targeted `computer-use` skill, **not** Hermes' built-in `computer_use` tool/toolset. The plugin receives the tool-override capability and wraps that existing tool. Terminal access is optional helper machinery; ordinary desktop control requires only `computer_use`.

The installer also pins the exact Cua identity used by integrated Hermes profiles, restarts affected running gateways after integration/environment repair, and proves the live gateway environment before readiness can succeed.

## Exact foreground

Foreground is the informed fresh-install default. `/computer-use background on|off|status` changes the standing preference; explicit task intent wins.

If a native `computer_use` action does not specify delivery mode, GWCU applies this preference. Action spans use the same setting.

The high-level foreground path is:

```text
ACQUIRE    closed local app → Cua launch → bind one exact NEW (pid, window_id)
DISCOVER   running target → exact (pid, window_id)
PRESENT    Cua GNOME helper → focused + visible + not minimized proof
ACT        Cua mutates that exact target
REVALIDATE identity when it changes
COMPLETE   present + verify the final visible result when required
```

**No exact `(pid, window_id)` proof, no focus-bound input.** Visible-result requests end visibly. A background-unavailable fallback may escalate through the same PRESENT gate once.

The exhaustive foreground action matrix belongs in `SKILL.md`. Hermes native actions are gated by the policy plugin; local spans cover every Cua tool exposing `delivery_mode`, so new tools inherit the gate.

## WORLDLINE

WORLDLINE turns repeated observation loops into local predicate-driven continuation:

```text
click Save → document.dirty == false → predicate satisfied → continue
```

Standalone WORLDLINE owns one private socket and revision store for GWCU and other consumers. It reads AT-SPI, direct host facts and exact Cua GNOME compositor frames, with ScreenCast/PipeWire evidence when requested. GWCU's observer remains a separate visual sensor.

Horner can use the same WORLDLINE protocol 1 socket for its foreground and
body receipts. A receipt is valid only in the daemon instance named by its
`domain_id`; nested Horner DevKits use their own socket and revision domain.
The receipt's `claim` states the proved boundary: verified foreground focus
does not prove that a click achieved the user's application goal.

For awaited actions, the runtime seals a WORLDLINE fence after presentation and immediately before Cua mutates the target. Postconditions must then be evidenced in a newer revision: a cached fact that was already true before the action cannot complete the action.

## `.gwcu`

`.gwcu` stores stable local truth only. It never stores screenshots, documents, credentials, transient focus/geometry or WORLDLINE revisions. Live Cua/WORLDLINE evidence wins on contradiction.

Scope order: `GWCU_SCOPE_ROOT` → Git worktree root → nearest ancestor already containing `.gwcu` → current directory. Git scopes add `/.gwcu` to `.gitignore` before managed truth is written.

## Install

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

## Update

From the existing checkout, after updating standalone WORLDLINE, run:

```bash
./update.sh
```

This fast forwards the current branch and reruns the local installer to update
the installed skill, policy and runtime. It stops if the checkout has local
changes. The installer may request desktop consent or a GNOME sign-out/sign-in;
follow its `Next:` guidance and rerun `./update.sh` after signing back in.

Install and start [standalone WORLDLINE](https://github.com/ryanraposo/WORLDLINE) first. The installer verifies its versioned socket, then qualifies Ubuntu 26.04 GNOME Wayland, installs/reuses pinned Cua and its helper, establishes portal consent, installs the skill/runtime and Hermes policy, enables the visual observer, retires the embedded GWCU WORLDLINE units, and live-proves readiness.

Other runtimes can call `scripts/gwcu-exec` with a JSON action span on stdin. The executable owns exact foreground admission and Cua action delivery; its redacted trace and WORLDLINE causal receipts describe the outcome without requiring the text of this skill.

`READY // PROVED` requires the installed Cua identity, Hermes-selected identity, running gateway backend identity and doctor-reported identity to agree. A split-brain version/path state fails readiness.

For an existing local checkout, `bash install.sh` repairs its installed
observer socket and imports the live desktop environment into systemd and
affected Hermes gateways. Check the result with
`bash scripts/computer-use.sh doctor`; `desktop_environment_unproved` means
the gateway still lacks the GNOME session environment, and
`observation_degraded` identifies unavailable observer components. The live
Calculator acceptance test additionally proves exact window presentation,
an observed application result, and removal of its named agent cursor session.
Its cursor visibility field may remain unverified even when the input result
is verified.

If the GNOME helper needs a session reload, the installer asks for one sign-out/sign-in and does not claim fully proved readiness until rerun.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Public uninstall uses the same verified release source. Teardown removes GWCU-managed integration/transient state, restores archives where possible, preserves workspace `.gwcu`, and leaves built-in `computer_use` alone. Cua is preserved by default; `--remove-cua` removes a GWCU-provisioned copy and `--purge-cua` is explicit full purge.
