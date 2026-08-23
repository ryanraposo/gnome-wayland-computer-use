```text
                          ▄  ▄▄  ▄▄▄▄
                             ▄▀ 0x0 ▀▄
                              █  ───  █
                              █  ███  █
                               ▀▀   ▀▀
```

# gnome-wayland-computer-use

Agents have variable success using Linux. GWCU makes computer use dependable on Ubuntu 26 GNOME Wayland by putting one desktop actuator behind a small local world model.

[Install](#install) · [Use it](#use-it) · [Hermes](#hermes-integration) · [Control](#control) · [WORLDLINE](#why-worldline-exists) · [`.gwcu`](#gwcu) · [Invariants](#invariants)

---

**Cua controls. WORLDLINE knows. `.gwcu` remembers.**

```text
model decides
→ exact target is established
→ Cua acts
→ WORLDLINE revises what changed
→ expected postcondition becomes true
→ continue locally
```

Observation is an interrupt, not a ritual RPC. Facts are valid until invalidated.

## What it is

| Layer | Job |
|---|---|
| **Cua Driver** | The only desktop actuator: native windows, browser-backed surfaces, pointer/keyboard, semantics, pixels and verification. |
| **Cua GNOME helper** | Exact persistent presentation of a known `(pid, window_id)` before foreground input. |
| **WORLDLINE** | Transient revisioned state, invalidation, predicates, waits, branches and conflicts. |
| **`.gwcu`** | Durable repo/workspace truth worth reusing in another session. |

On GNOME Wayland, Cua uses `org.freedesktop.portal.RemoteDesktop` → EIS/libei for compositor-approved local input. GNOME may label that permission **Remote Desktop** or **remote control**. GWCU installs no RDP/VNC server and no raw-input daemon. **No X11 or XWayland session is required.**

## Use it

The installed Hermes skill owns `/computer-use` task dispatch:

```text
/computer-use open YouTube and play something
/computer-use rename this file and put it in Downloads
/computer-use send the message I drafted
```

Reserved operators, all published to Hermes completion:

```text
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

`computer-use.sh span` is internal-only.

## Hermes integration

GWCU deliberately joins two different Hermes layers whose names are easy to confuse:

```text
computer-use          Hermes skill / /computer-use operating contract
      │
      ▼
GWCU policy plugin    mechanical presentation + delivery policy
      │
      ▼
computer_use          Hermes built-in tool/toolset
      │
      ▼
Cua Driver            actuator
```

**GWCU replaces the `computer-use` skill; it does not replace the `computer_use` tool.** The skill tells the agent how computer use works. The enabled GWCU plugin receives Hermes' `tools.override` capability and wraps the existing `computer_use` tool so exact foreground presentation and delivery policy are enforced mechanically. Cua remains the actuator underneath.

For each targeted Hermes home the installer:

1. installs GWCU at `skills/computer-use`;
2. archives an existing non-GWCU `computer-use` skill instead of deleting it;
3. installs and enables only the GWCU policy plugin;
4. clears stale disabled state and grants only `tools.override`;
5. verifies that the plugin is actually enabled in that profile.

The default Hermes home is integrated automatically. Additional existing profiles are explicit:

```bash
# default Hermes home + one profile
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh \
  | bash -s -- --hermes-profile work

# default Hermes home + every existing profile
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh \
  | bash -s -- --hermes-all-profiles
```

`--hermes-profile NAME` is repeatable. A profile created after GWCU was installed is untouched until selected on a later installer run. A profile that intentionally contains no bundled skills stays that way: selecting it adds GWCU's single `computer-use` skill and policy plugin; the installer does not seed the Hermes skill library.

GWCU does not disable Hermes' separate `browser` toolset globally. While `/computer-use` is active, the skill contract keeps browser actuation on Cua's typed-browser or native AX/PX routes. Other Hermes workflows remain free to use their own configured toolsets.

Teardown is the inverse. Because the host runtime is shared, uninstall scans the default Hermes home and every existing profile, removes only directories carrying GWCU's managed marker, revokes GWCU's plugin enablement/override grant, and restores archived pre-GWCU components when their original destination is free. The built-in `computer_use` tool/toolset is untouched.

### Browser work is still computer use

`/computer-use` never jumps to Hermes' separate browser automation plane. Cua remains the actuator.

- Supported Chromium/Electron page work uses Cua only after exact native `(pid, window_id)` binding.
- Firefox, browser chrome and unsupported typed routes stay on Cua's native AX/PX path.
- Typed page success does not imply that the browser window is visible.
- A hidden/headless/managed browser success is failure when visibility is part of the request.

## Control

`/computer-use background` toggles the standing delivery preference:

```text
OFF  → exact visible takeover (default)
ON   → background where Cua can deliver it safely
```

There is no confidence threshold. Missing foreground words never silently select background.

### Exact visible takeover

Cua's action-scoped `delivery_mode:"foreground"` may briefly activate a target and restore the previous frontmost window. GWCU therefore makes persistent presentation a separate precondition.

With background priority OFF, the path is mechanically pre-traced:

```text
1 DISCOVER
  Cua list_windows → exact intended (pid, window_id)

2 PRESENT
  attested Cua GNOME helper → Activate(window_id)
  → exact row must be focused=true, visible=true, minimized=false
  → otherwise no input is sent

3 ACT
  Cua mutation against the same pid + window_id
  → delivery_mode="foreground"

4 REVALIDATE
  if native identity changed, resolve it again before focus-bound input

5 COMPLETE VISIBLY
  re-present final exact target → verify requested state → leave it visible
```

This is enforced twice: direct Hermes `computer_use` is wrapped by GWCU's enabled policy plugin, and multi-action work goes through `action-span.py`. Both fail closed before foreground input if exact presentation cannot be proved.

A visible-result request always carries step 5 even when the user explicitly chose background work for the intermediate actions.

## Why WORLDLINE exists

Ordinary GUI automation repeatedly pays the model to rediscover expected outcomes:

```text
observe → model → click → observe → model → type → observe → model
```

GWCU keeps already-known mechanics local:

```text
click Save
→ document.dirty == false
→ predicate satisfied
→ continue
```

WORLDLINE ingests authoritative facts from AT-SPI, filesystem/process state, D-Bus, settings, network/task watchers and, when necessary, visual evidence. Revisions invalidate affected dependencies while unrelated facts survive. WORLDLINE never injects input.

## `.gwcu`

`.gwcu` stores low-churn local truth such as app identity, capability conclusions, calibration and user-authored preferences. It never stores screenshots, documents, credentials, task history, transient focus/geometry, presentation guesses or WORLDLINE revisions.

```text
GWCU_SCOPE_ROOT override
→ Git worktree root
→ nearest non-Git ancestor already containing .gwcu
→ current directory
```

Git worktrees add `/.gwcu` to the root `.gitignore` before managed truth is written. Live Cua/WORLDLINE evidence wins on contradiction.

## Install

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/install.sh | bash
```

The installer qualifies Ubuntu 26.04 GNOME Wayland; repairs Git, portal, PipeWire, AT-SPI and Python GI dependencies; installs or reuses pinned Cua Driver `0.20.0` and its GNOME helper; establishes RemoteDesktop consent; deploys the skill; **replaces the targeted Hermes `computer-use` skill while preserving the built-in `computer_use` tool, enables the GWCU policy plugin and grants its single declared `tools.override` capability** when Hermes is installed; configures `.gwcu` and background priority; enables WORLDLINE and the lazy observer; repairs known old GWCU artifacts; and live-proves Cua, exact presentation, WORLDLINE and observation before printing `READY // PROVED`.

If GNOME Shell has not loaded a newly installed helper yet, the installer says exactly that, asks for one sign-out/sign-in, and does **not** claim fully proved readiness. Rerunning the installer after login finishes the live presentation proof.

Every run writes a private install log and a machine-readable receipt under `~/.local/state/gnome-wayland-computer-use/`. The receipt records how many Hermes homes were integrated.

Run it as the logged-in desktop user, not by wrapping it in `sudo`.

## Uninstall

```bash
curl -fsSL https://ryanraposo.github.io/gnome-wayland-computer-use/uninstall.sh | bash
```

Teardown removes only GWCU-owned integration and transient runtime state. It cleans GWCU-managed skill/plugin integration from the default Hermes home and all existing profiles, restores archived components where possible, and leaves Hermes' built-in `computer_use` tool/toolset alone. Repo/workspace `.gwcu` content survives. Cua is preserved by default; `--remove-cua` removes only a GWCU-provisioned installation and `--purge-cua` is the explicit full purge.

## Invariants

- **Cua is the only actuator.** Native apps and browser work share one control authority.
- **GWCU owns the `computer-use` skill, not the `computer_use` tool.** Hermes keeps its built-in tool surface; GWCU wraps its policy while enabled.
- **Profile integration is explicit; teardown is complete.** Install targets only selected Hermes homes; uninstall removes every GWCU-managed profile integration before the shared runtime disappears.
- **Foreground means exact presentation first.** No exact `(pid, window_id)` proof, no focus-bound input.
- **Visible requests end visibly.** Hidden success is not completion.
- **Background OFF means visible takeover.** Missing intent metadata cannot reverse it.
- **WORLDLINE is read-only knowledge machinery.** Events and predicates never gain input authority.
- **Postconditions replace ritual observation.** Model calls happen at decision boundaries.
- **`.gwcu` is durable only.** Runtime state stays transient.
- **Direct truth beats pixels.** Visual evidence is escalation, not ceremony.

## Project map

```text
SKILL.md                  runtime behavior contract
AGENTS.md                 repository/install instructions for agents
scripts/present-window.py exact Cua/GNOME presentation gate
scripts/action-span.py    one-session Cua spans + control policy
scripts/worldline.py      revision store, predicates, waits, conflicts
scripts/profile.sh        app routing, truth composition, recovery
scripts/truths.py         .gwcu scope and persistence
scripts/observer.py       warm ScreenCast/PipeWire visual sensor
scripts/computer-use.sh   developed operator subcommands
runtimes/hermes/          enabled policy + completion integration
install.sh                qualified install / upgrade / profile integration / proof
uninstall.sh              safe removal entry point
```
