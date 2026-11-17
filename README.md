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

`SKILL.md` is the canonical agent contract: routing, foreground, acquisition, verification, browser continuity and failure boundaries.

GWCU uses **Cua Driver's MCP/tool surface**; GWCU itself is not another MCP server. The runtime makes the contract mechanical, not advisory.

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

The Cua logon daemon is a GWCU user unit starting pinned `cua-driver serve` at `graphical-session.target`, live-proved with `cua-driver status`. User-owned Cua autostart is preserved, not displaced.

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

Examples: `/computer-use open YouTube and play something`.

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

Routes can switch mid-task, but a targeted browser session keeps its UI mutations on Cua so identity, tab state and completion evidence stay coherent.

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

GWCU replaces the targeted `computer-use` skill, **not** Hermes' built-in `computer_use` tool/toolset. The plugin wraps that tool with tool-override capability; terminal access is optional.

The installer pins Cua identity for integrated Hermes profiles, restarts affected gateways after repair, and proves the live environment before readiness.

### Hermes skill tap

```bash
hermes skills tap add ryanraposo/gnome-wayland-computer-use
hermes skills install ryanraposo/gnome-wayland-computer-use/computer-use
```

The tap serves `skills/computer-use/SKILL.md` (byte-identical to root `SKILL.md`); it does not replace the installer, which still supplies the plugin, Cua logon daemon, helper, consent and WORLDLINE.

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

The exhaustive foreground action matrix belongs in `SKILL.md`. The policy plugin gates Hermes actions; local spans cover every Cua tool exposing `delivery_mode`.

## WORLDLINE

WORLDLINE turns repeated observation loops into local predicate-driven continuation:

```text
click Save → document.dirty == false → predicate satisfied → continue
```

Standalone WORLDLINE owns one private socket and revision store. It is independently installed, reads AT-SPI, host facts and ScreenCast/PipeWire frames when requested, and stays read-only. GWCU's observer is a separate visual sensor.

Horner can share the WORLDLINE socket; receipts are valid only in the named `domain_id`. GWCU's installer and doctor require the `receipt` op, so a stale WORLDLINE fails closed at install.

For awaited actions, the runtime seals a WORLDLINE fence after presentation and immediately before Cua mutates the target. Postconditions must then be evidenced in a newer revision: a cached fact that was already true before the action cannot complete the action.

## `.gwcu`

`.gwcu` stores stable local truth only. It never stores screenshots, documents, credentials, transient focus/geometry or WORLDLINE revisions. Live Cua/WORLDLINE evidence wins on contradiction.

Scope order: `GWCU_SCOPE_ROOT` → Git worktree root → nearest ancestor already containing `.gwcu` → current directory. Git scopes add `/.gwcu` to `.gitignore` before managed truth is written.

## Install

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

Run in a new, visible terminal on the desktop. Install and start [standalone WORLDLINE](https://github.com/ryanraposo/WORLDLINE) first. The installer verifies one SHA-256 release archive, qualifies Ubuntu 26.04 GNOME Wayland, installs/reuses pinned Cua, enables its logon daemon, establishes portal consent, installs the skill/runtime and Hermes policy, and live-proves readiness. If the RemoteDesktop portal is missing, it opens GNOME Settings -> Sharing -> Remote Desktop (Screen Sharing) and waits for you; you still approve GNOME's prompt.

If the installer prints `STOP: SIGN OUT / SIGN IN REQUIRED`, follow its steps: save work, sign out of GNOME, sign back in as the same user, rerun the install command. Only `READY // PROVED` means ready.

## Update

From an existing checkout after updating WORLDLINE, run `./update.sh`. It fast forwards the branch and reruns the local installer; follow its `Next:` guidance through consent or a GNOME sign-out/sign-in.

Other runtimes can call `scripts/gwcu-exec` with a JSON action span on stdin. The executable owns exact foreground admission and Cua action delivery; its redacted trace and WORLDLINE causal receipts describe the outcome without requiring the text of this skill.

`READY // PROVED` requires the installed Cua identity, Hermes-selected identity, running gateway backend identity and doctor-reported identity to agree. A split-brain version/path state fails readiness.

For an existing checkout, `bash install.sh` repairs the observer socket and imports the live desktop environment into systemd and affected Hermes gateways. Check with `bash scripts/computer-use.sh doctor`; `desktop_environment_unproved` and `observation_degraded` name the respective gaps. The live Calculator test proves exact presentation, an observed result and removal of the agent cursor session.

## Release

Ship from `dev` via a `release/<version>-main` PR into `main` with all version strings aligned. After main CI is green, push annotated tag `v<version>` at the main commit: `.github/workflows/release.yml` builds from that commit, uploads the archive and checksum manifest to the GitHub Release, and verifies the published URL. Fast-forward `dev` afterwards.

Pages serves bootstrap scripts and `VERSION`; artifacts use the versioned Release URL (`GWCU_RELEASE_URL` overrides it). A push to `main` deploys those bytes and `tests/pages-freshness.sh` verifies them; stale Pages is a release blocker.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Public uninstall uses the same verified release source. Teardown removes GWCU-managed integration/transient state and the GWCU Cua logon unit, restores archives where possible, preserves workspace `.gwcu`, and leaves built-in `computer_use` alone. User-owned Cua autostart is preserved; Cua itself is preserved by default, `--remove-cua` removes a GWCU-provisioned copy and `--purge-cua` is explicit full purge.
