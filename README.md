```text
                          ▄  ▄▄  ▄▄▄▄
                             ▄▀ 0x0 ▀▄
                              █  ───  █
                              █  ███  █
                               ▀▀   ▀▀
```

# gnome-wayland-computer-use

Agents have variable success using Linux. GWCU makes computer use dependable on Ubuntu 26 GNOME Wayland by putting one desktop actuator behind a small local world model.

**Cua controls. WORLDLINE knows. `.gwcu` remembers.**

```text
model decides → exact target → Cua acts → WORLDLINE revises truth
→ expected postcondition becomes true → continue locally
```

Observation is an interrupt, not a ritual RPC. Facts are valid until invalidated.

## What it is

| Layer | Job |
|---|---|
| **Cua Driver** | Only desktop actuator: native apps, the user's browser, input, semantics, pixels, verification. |
| **Cua GNOME helper** | Exact persistent presentation of `(pid, window_id)`. |
| **WORLDLINE** | Transient revisioned state, invalidation, predicates, waits and conflicts. |
| **`.gwcu`** | Durable low-churn machine/workspace truth. |

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

`computer-use.sh span` is internal-only.

## Tool boundaries

GWCU owns **physical computer use**, not every browser or shell task.

```text
web as information                       → browser/web tooling
user's real browser session or browser UI→ Cua
ordinary shell / CLI work                → terminal tool
terminal window used physically          → Cua
```

Research, reading, retrieval and web navigation can use normal web/browser tools when the user's browser state is irrelevant. Existing login/session, tabs, browser chrome, placement and visible browser experience are desktop state, so Cua owns their actuation.

Ordinary command-line work belongs to the terminal tool. Terminal is optional machinery for GWCU helper scripts, not part of the skill's domain or discovery requirement. A mixed task can cross these boundaries freely.

## Hermes

```text
computer-use skill
      ↓
GWCU policy plugin
      ↓
computer_use built-in tool
      ↓
Cua Driver
```

GWCU replaces the targeted `computer-use` skill, **not** Hermes' built-in `computer_use` tool/toolset. The plugin gets only `tools.override`, wrapping the existing tool to enforce delivery policy and exact foreground presentation.

The skill declares only `requires_toolsets: [computer_use]`. GWCU does not broaden a profile's tool policy. Existing non-GWCU skills are archived before replacement; teardown restores them when possible.

Web tooling remains available globally. For the **user's actual browser**, supported Chromium/Electron page work binds exact native `(pid, window_id)` before typed mutation; Firefox, browser chrome and unsupported routes stay on Cua's native AX/PX path. Web used merely as information remains free to use browser/web tooling.

## Control preference

A fresh interactive install explains this choice and asks once. **Foreground is the default.**

```text
Foreground / background OFF
  exact target is presented; may take over your screen

Background / background ON
  keep your current window in front where Cua supports it
```

Visible-result requests still finish visibly. Explicit foreground/background wording always wins over the standing preference.

Change it later:

```text
/computer-use background on       prefer background work
/computer-use background off      prefer exact visible takeover
/computer-use background status   show current preference
/computer-use background          toggle
```

The preference spreads to otherwise-unspecified native `computer_use` input through GWCU's Hermes policy wrapper and to action spans. It does not claim unrelated web research or shell work.

### Exact foreground

Background OFF pre-traces:

```text
DISCOVER  Cua list_windows → exact (pid, window_id)
PRESENT   attested GNOME helper → Activate(window_id) → focused+visible proof
ACT       same target → delivery_mode="foreground"
REVALIDATE if native identity changes
COMPLETE  present and verify the final visible result when required
```

**No exact `(pid, window_id)` proof, no focus-bound input.** Direct Hermes calls and multi-action spans both fail closed before foreground input if exact presentation cannot be proved.

If background delivery is explicitly unavailable, GWCU may fall forward once through the same exact presentation gate. There is no floating confidence threshold.

## WORLDLINE

Ordinary GUI automation often pays the model to rediscover expected outcomes:

```text
click Save → screenshot → model → wait → screenshot → model
```

GWCU can instead state the expected consequence:

```text
click Save → document.dirty == false → predicate satisfied → continue
```

WORLDLINE ingests authoritative facts from AT-SPI, filesystem/process state, D-Bus, settings, network/task watchers and visual evidence only when needed. It never injects input. Cua remains the sole actuator.

WORLDLINE is socket-activated. Health: `worldline.py request --json '{"op":"status"}'`.

## `.gwcu`

`.gwcu` stores stable identity, capabilities, calibration and user-authored preferences. It never stores screenshots, documents, credentials, transient focus/geometry or WORLDLINE revisions. Live Cua/WORLDLINE evidence wins on contradiction.

Scope order: `GWCU_SCOPE_ROOT` → Git worktree root → nearest ancestor already containing `.gwcu` → current directory. Git scopes add `/.gwcu` to `.gitignore` before managed truth is written.

## Install

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

The installer qualifies Ubuntu 26.04 GNOME Wayland, installs/reuses Cua Driver `0.20.0` plus its helper, establishes portal consent, installs the skill/runtime and Hermes policy, configures preferences, enables WORLDLINE/observation, repairs older GWCU artifacts, and live-proves readiness.

On a fresh interactive install it explains:

```text
Foreground (default): presents the exact target and may take over your screen.
Background: keeps your current window in front where Cua supports it.
Visible-result requests still finish visibly.
Change later: /computer-use background on|off|status
```

Then it asks `Use exact visible takeover as your default? [Y/n]`. `--unattended` accepts foreground. The setting changes later without reinstalling.

If the GNOME helper needs a session reload, the installer asks for one sign-out/sign-in and does not claim fully proved readiness until rerun.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Teardown removes GWCU-owned integration/transient state, restores archives where possible, preserves workspace `.gwcu`, and leaves built-in `computer_use` alone. Cua is preserved by default; `--remove-cua` removes a GWCU-provisioned copy and `--purge-cua` is explicit full purge.

## Invariants

- Cua is the only **desktop** actuator.
- Web-as-information is free to use browser/web tooling.
- Ordinary shell work belongs to terminal; a physically operated terminal window belongs to Cua.
- Foreground is the informed fresh-install default; `/computer-use background` changes the standing preference.
- Visible requests end visibly.
- No exact target/presentation proof means no focus-bound input.
- WORLDLINE knows; it never acts.
- Direct truth beats pixels; model calls happen at decision boundaries.
- `.gwcu` stores durable truth only.
