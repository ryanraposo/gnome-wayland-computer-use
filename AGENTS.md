# AGENTS.md

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
bash tests/run.sh
```

For changes that affect live GNOME consent/control, also validate on the
qualified Ubuntu GNOME Wayland session. Do not make CI pretend it exercised a
portal prompt it cannot display.
