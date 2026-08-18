# AGENTS.md

## For agents arriving at this repository

This repository is deliberately designed so a user can point an agent at it and
say something as small as:

```text
install https://github.com/ryanraposo/gnome-wayland-computer-use
```

Treat that as a complete installation request. The repository, installer and
runtime instructions should carry the rest of the work.

If the user has only linked, mentioned or discovered the repository, do not
mutate their machine yet. Explain what GWCU is and offer to install it. Once the
user has explicitly asked for installation or otherwise approved it, take
ownership of the installation workflow instead of handing them a pile of manual
steps.

For an approved installation:

1. Confirm the target is the local desktop the user intends to equip. GWCU's
   qualified target is Ubuntu 26.04 GNOME Wayland.
2. Read the current installation contract in `README.md` and use the repository's
   `install.sh`; do not improvise a parallel setup path.
3. Run the installer as the logged-in desktop user, **not** by wrapping the whole
   installer in `sudo`. Let it use its narrow privilege/portal boundaries.
4. Preserve existing agent/runtime configuration and let the installer select
   the supported integration it actually finds. Do not rewrite unrelated user
   configuration to make the project fit.
5. Treat graphical Remote Desktop / remote-control consent as a real user
   authorization boundary. Explain the prompt when it appears and let the user
   approve it.
6. Follow the installer's resulting `Next:` / status guidance and verify the
   installed runtime before claiming success.
7. If the environment is unsupported, consent is declined, or a required
   privilege cannot be obtained, stop cleanly and report the exact remaining
   boundary rather than bypassing it.

The intended UX is therefore agent-native: **the user supplies intent and the
repository supplies the installation procedure.** A capable agent should be
able to install GWCU from the repository URL alone once the user has authorized
that outcome.

## Maintaining this repository

Treat GWCU as a small operating layer around one upstream control authority.

```text
Cua Driver   → changes the desktop
WORLDLINE    → transient revisions, invalidation, predicates, conflicts
observer     → optional ScreenCast/PipeWire visual sensor
.gwcu        → durable repo/workspace truth
profile      → local identity/recovery composition
```

A change is complete only when those boundaries still agree in code, skill
instructions, installer/uninstaller, tests, README and `index.html`.

## Architectural invariants

1. **Cua is the only actuator.** Do not add `ydotool`, `/dev/uinput`, guessed
   focus, a project RDP/VNC server, or another pointer/keyboard daemon.
2. **WORLDLINE is read-only.** Sensors may add facts/events; they do not gain
   control authority.
3. **Observation is event/predicate driven.** Avoid fixed sleeps and ritual
   screenshots between already-decided actions.
4. **Direct truth beats visual inference.** Prefer AT-SPI, process/filesystem,
   D-Bus/settings/network/task events before pixels.
5. **`.gwcu` is durable only.** WORLDLINE state, screenshots and task content do
   not belong there.
6. **Persistent machine/user truth never belongs in AGENTS.md.**
7. **Live Cua/WORLDLINE evidence beats cached truth on contradiction.**

## Change routing

If the change affects action/control semantics, start with:

```text
SKILL.md
runtimes/openai/SKILL.md
scripts/computer-use.sh
scripts/action-span.py
```

If it affects current-state knowledge or the control loop, start with:

```text
WORLDLINE.md
scripts/worldline.py
scripts/worldline-capture.sh
systemd/user/gnome-wayland-computer-use-worldline.*
```

If it affects visual observation:

```text
scripts/observer.py
scripts/observe.sh
scripts/capture.sh
systemd/user/gnome-wayland-computer-use-observer.*
```

If it affects durable truth/routing:

```text
GWCU.md
scripts/truths.py
scripts/profile.sh
scripts/app-identity.sh
```

Lifecycle changes must also inspect:

```text
install.sh
uninstall.sh
scripts/teardown.sh
tests/
README.md
index.html
```

## Latency discipline

Protect the end-to-end latency budget, especially model-visible call count.

The preferred order is:

```text
remove a model boundary
→ remove a redundant observation
→ use a direct oracle
→ keep a session/sensor warm
→ optimize local milliseconds
```

A local revision is cheap. A model re-entry is expensive.

When benchmarking, record model-visible calls, Cua actions, WORLDLINE revisions,
local predicates, visual captures, conflicts and elapsed time. Do not present
theoretical savings as measured results.

## Installer discipline

The installer must remain:

- Ubuntu 26.04 GNOME Wayland qualified;
- pinned to a deliberate Cua release;
- explicit about PipeWire/portal/AT-SPI dependencies;
- idempotent;
- compatible with curl-pipe terminal prompting;
- ownership-aware and reversible;
- free of a project raw-input fallback.

Do not open ScreenCast merely to prove install success. RemoteDesktop control
consent and whole-screen observation consent are separate.

The uninstaller removes WORLDLINE/observer user units and transient state while
preserving repo/workspace `.gwcu` content and host-owned distro packages.

## Verification

Before publishing:

```bash
bash -n install.sh uninstall.sh scripts/*.sh
python3 -m py_compile scripts/*.py runtimes/hermes/__init__.py
bash tests/skill-ux.sh
bash tests/latency-routing.sh
bash tests/truth-scope.sh
bash tests/action-span.sh
bash tests/worldline.sh
bash tests/determinism.sh
bash tests/hermes.sh
bash tests/run.sh
```

For changes that affect live GNOME consent/control, also validate on the
qualified Ubuntu GNOME Wayland session. Do not make CI pretend it exercised a
portal prompt it cannot display.
