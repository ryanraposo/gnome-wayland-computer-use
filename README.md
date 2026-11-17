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
| **WORLDLINE window observations** | Supplies fresh compositor-verified identity, geometry, focus, visibility and lifecycle facts. It never activates or injects input. |
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

The tap serves `skills/computer-use/SKILL.md` (byte-identical to root `SKILL.md`); it does not replace the installer, which still supplies the plugin, Cua logon daemon, portal consent and WORLDLINE.

## Exact foreground

Foreground is the informed default; `/computer-use background on|off|status` changes the standing preference, and explicit task intent wins. GWCU never activates arbitrary windows. Foreground input requires the exact CUA `(pid, window_id)` to map through WORLDLINE's `cua_window_id` to one fresh, compositor-verified, focused and visible window. No proof, no focus-bound input.

```text
ACQUIRE    Cua launch or discover → bind exact (pid, window_id)
ADMIT      WORLDLINE exact identity + fresh compositor geometry + already-focused proof
ACT        Cua mutation
REVALIDATE before each later foreground mutation
COMPLETE   verify final visible state when requested
```

A visible-result request is incomplete unless WORLDLINE verifies the exact target is focused and visible. Background-unavailable fallback uses the same admission gate. Cua `set_value` remains available through the semantic background route; foreground delivery is still gated.

GNOME 50+ modes: **full foreground** unsupported pending a qualified Cua activation adapter; **verified foreground** requires exact identity + compositor geometry + RemoteDesktop input; **semantic interaction** uses AT-SPI; **desktop visual** is optional ScreenCast/PipeWire + RemoteDesktop; **observe-only** is the safe fallback. Available, unavailable, denied and stale states are explicit. Desktop capture does not gate semantic operation.

The full action matrix and policy rules live in `SKILL.md`. The Hermes plugin gates foreground actions; local action spans revalidate WORLDLINE before dispatch and preserve the newer-revision postcondition fence.
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

Run in a new visible desktop terminal. Install [standalone WORLDLINE](https://github.com/ryanraposo/WORLDLINE) first. The installer verifies its SHA-256 release, qualifies Ubuntu 26.04 GNOME Wayland, installs pinned Cua, enables its daemon, establishes portal consent, installs the skill/runtime and Hermes policy, and checks WORLDLINE capabilities. It never installs or enables WinRects; existing installations are disabled and verified inactive. If RemoteDesktop consent is missing, it opens GNOME Settings and waits for your approval. `READY // PROVED` follows only after capability checks succeed.

## Update

After updating WORLDLINE, run `./update.sh` from an existing checkout and follow its `Next:` guidance. Other runtimes can call `scripts/gwcu-exec` with a JSON action span; it owns admission and Cua delivery, while its redacted trace and WORLDLINE receipts record outcomes.

`READY // PROVED` requires the installed Cua, Hermes, gateway and doctor identities to agree; split-brain paths fail readiness.

## Release

Ship from `dev` via a `release/<version>-main` PR into `main` with all version strings aligned. After main CI is green, push annotated tag `v<version>` at the main commit: `.github/workflows/release.yml` builds from that commit, uploads the archive and checksum manifest to the GitHub Release, and verifies the published URL. Fast-forward `dev` afterwards.

Pages serves bootstrap scripts and `VERSION`; artifacts use the versioned Release URL (`GWCU_RELEASE_URL` overrides it). A push to `main` deploys those bytes and `tests/pages-freshness.sh` verifies them; stale Pages is a release blocker.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Public uninstall uses the same verified release source. Teardown removes GWCU-managed integration/transient state and the GWCU Cua logon unit, restores archives where possible, preserves workspace `.gwcu`, and leaves built-in `computer_use` alone. User-owned Cua autostart is preserved; Cua itself is preserved by default, `--remove-cua` removes a GWCU-provisioned copy and `--purge-cua` is explicit full purge.
