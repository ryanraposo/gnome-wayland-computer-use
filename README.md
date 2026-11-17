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
| **Cua logon daemon** | GWCU systemd unit running pinned `cua-driver serve` at graphical logon. |
| **Cua GNOME helper** | Presents one exact `(pid, window_id)` and proves focused + visible state. |
| **GWCU local runtime** | Installer, doctor, action spans, presentation helpers, routing and lifecycle repair. |
| **WORLDLINE** | Transient revisioned state, invalidation, predicates, waits and conflicts. Read-only: it never injects input. |
| **`.gwcu`** | Durable low-churn machine/workspace truth such as stable identity, capabilities, calibration and preferences. |

GNOME Wayland uses the `Remote Desktop` portal → EIS/libei for compositor-approved local input. GWCU installs no RDP/VNC server or raw-input daemon. **No X11 or XWayland session is required.**

The Cua daemon is standard: a GWCU-owned `gnome-wayland-computer-use-cua-driver.service` user unit starts the pinned `cua-driver serve` at `graphical-session.target`, live-proved with `cua-driver status`. Enabled upstream/user Cua autostart is preserved, not displaced by a second daemon.

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

### Hermes skill tap

The agent-facing contract is published as a Hermes skill tap, so `computer-use` can be discovered and updated through the Skills Hub:

```bash
hermes skills tap add ryanraposo/gnome-wayland-computer-use
hermes skills install ryanraposo/gnome-wayland-computer-use/computer-use
```

The tap serves `skills/computer-use/SKILL.md`, which is byte-identical to the root `SKILL.md`. It does not replace the installer: the policy plugin, pinned Cua logon daemon, exact-foreground helper, portal consent and WORLDLINE dependency still come from `install.sh`. Install on the desktop host first, then use the tap to keep the skill contract current.

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

Standalone WORLDLINE owns one private socket and revision store for GWCU and other consumers. It is independently installed and managed, reads AT-SPI, direct host facts and exact Cua GNOME compositor frames with ScreenCast/PipeWire evidence when requested, and remains read-only. GWCU's observer is a separate visual sensor.

Horner can use the same WORLDLINE protocol 1 socket for foreground and body receipts. A receipt is valid only in the daemon instance named by its `domain_id`; nested Horner DevKits use their own socket and revision domain. GWCU's installer and doctor require the `receipt` op, so a stale WORLDLINE fails closed at install instead of mid-action.

For awaited actions, the runtime seals a WORLDLINE fence after presentation and immediately before Cua mutates the target. Postconditions must then be evidenced in a newer revision: a cached fact that was already true before the action cannot complete the action.

## `.gwcu`

`.gwcu` stores stable local truth only. It never stores screenshots, documents, credentials, transient focus/geometry or WORLDLINE revisions. Live Cua/WORLDLINE evidence wins on contradiction.

Scope order: `GWCU_SCOPE_ROOT` → Git worktree root → nearest ancestor already containing `.gwcu` → current directory. Git scopes add `/.gwcu` to `.gitignore` before managed truth is written.

## Install

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

Run in a new, visible terminal on the desktop. Install and start [standalone WORLDLINE](https://github.com/ryanraposo/WORLDLINE) first. The installer verifies one commit-addressed SHA-256 release archive, qualifies Ubuntu 26.04 GNOME Wayland, installs/reuses pinned Cua plus its helper, enables the Cua logon daemon, establishes portal consent, installs the skill/runtime and Hermes policy, resolves WORLDLINE independently, and live-proves readiness. If the RemoteDesktop portal is missing, it opens GNOME Settings -> Sharing -> Remote Desktop (Screen Sharing) and waits for you to enable it; you still approve GNOME's prompt.

## Update

From an existing checkout after updating WORLDLINE, run `./update.sh`. It fast forwards the branch and reruns the local installer; follow its `Next:` guidance through consent or a GNOME sign-out/sign-in.

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

Public uninstall uses the same verified release source. Teardown removes GWCU-managed integration/transient state and the GWCU Cua logon unit, restores archives where possible, preserves workspace `.gwcu`, and leaves built-in `computer_use` alone. User-owned Cua autostart is preserved; Cua itself is preserved by default, `--remove-cua` removes a GWCU-provisioned copy and `--purge-cua` is explicit full purge.
