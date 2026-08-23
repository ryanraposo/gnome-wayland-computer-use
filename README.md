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

## What it is

| Layer | Job |
|---|---|
| **Cua Driver** | Sends desktop input and reads native/browser UI state. |
| **Cua GNOME helper** | Presents an exact `(pid, window_id)` and proves it is visible/focused. |
| **WORLDLINE** | Transient revisioned state, invalidation, predicates, waits and conflicts. |
| **`.gwcu`** | Durable low-churn machine/workspace truth. |

Here, *desktop actuation* simply means sending GUI input such as clicks, keys, scrolls and drags. GWCU keeps that input on Cua so targeting and verification use one consistent desktop path.

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

## Agent routing

Choose the route from the state the task needs next:

```text
desktop/native-app state or visible result → Cua
user's current browser session             → Cua
web content, research, reading, retrieval  → browser/web tooling
shell or CLI state                         → terminal tool
terminal window as visible desktop UI      → Cua
```

A task can move between these naturally: research with web tooling, run a CLI step through terminal, then use Cua when the task reaches the desktop.

When a task targets a specific browser window/session, keep that session's UI mutations on Cua so native window identity, page/tab state, visibility and completion evidence remain coherent. Supported Chromium/Electron page work binds exact native `(pid, window_id)` before typed mutation; Firefox, browser chrome and unsupported routes use Cua's native AX/PX path.

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

GWCU replaces the targeted `computer-use` skill, **not** Hermes' built-in `computer_use` tool/toolset. The plugin wraps that tool to apply the saved delivery preference and mechanically prove exact foreground presentation before native input.

The skill requires only `computer_use`. Terminal can accelerate GWCU's local helper scripts when available; ordinary computer use remains usable without it.

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

If a native `computer_use` action does not specify delivery mode, GWCU applies this preference. Action spans use the same setting.

### Exact foreground

Background OFF pre-traces:

```text
DISCOVER   Cua list_windows → exact (pid, window_id)
PRESENT    GNOME helper → Activate(window_id) → focused+visible proof
ACT        same exact target → delivery_mode="foreground"
REVALIDATE if native identity changes
COMPLETE   present and verify the final visible result when required
```

**No exact `(pid, window_id)` proof, no focus-bound input.** Direct Hermes calls and multi-action spans fail closed before foreground input if exact presentation cannot be proved.

If background delivery is explicitly unavailable, GWCU may fall forward once through the same presentation gate. There is no floating confidence threshold.

## WORLDLINE

A predictable consequence should not require repeated model turns:

```text
click Save → screenshot → model → wait → screenshot → model
```

becomes:

```text
click Save → document.dirty == false → predicate satisfied → continue
```

WORLDLINE ingests authoritative facts from AT-SPI, filesystem/process state, D-Bus, settings, network/task watchers and visual evidence only when needed. It never injects input.

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

Teardown removes GWCU-managed integration/transient state, restores archives where possible, preserves workspace `.gwcu`, and leaves built-in `computer_use` alone. Cua is preserved by default; `--remove-cua` removes a GWCU-provisioned copy and `--purge-cua` is explicit full purge.

## Invariants

- Route by the state the task needs next.
- All GWCU desktop GUI input goes through Cua.
- A specific user browser session stays on one Cua actuation path while it is being manipulated.
- Foreground is the informed fresh-install default; `/computer-use background` changes the standing preference.
- Visible requests end visibly.
- No exact target/presentation proof means no focus-bound input.
- WORLDLINE knows; it never acts.
- Direct truth beats pixels; model calls happen at decision boundaries.
- `.gwcu` stores durable truth only.
