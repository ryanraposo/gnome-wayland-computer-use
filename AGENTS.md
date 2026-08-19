# AGENTS.md

## For agents arriving at this repository

This repository is designed so a user can point an agent at it and say:

```text
install https://github.com/ryanraposo/gnome-wayland-computer-use
```

Treat that as a complete installation request. If the user has only linked or mentioned the repository, explain what it is and offer to install it. Once installation is approved, own the workflow instead of returning a pile of manual steps.

For an approved installation:

1. Confirm the target is the local desktop the user intends to equip. GWCU's qualified target is Ubuntu 26.04 GNOME Wayland.
2. Read `README.md`, then use the repository's `install.sh`. Do not invent a parallel setup path.
3. Run the installer as the logged-in desktop user, not by wrapping the whole installer in `sudo`.
4. Preserve unrelated agent/runtime configuration. Let the installer select the supported integration it actually finds.
5. Treat graphical Remote Desktop / remote-control consent as a real user authorization boundary. Explain the prompt and let the user approve it.
6. If Hermes asks for `tools.override`, explain that GWCU uses it only to make the built-in `computer_use` tool obey the saved foreground/background preference; do not hide or pre-answer that host-owned consent.
7. Follow the installer's resulting `Next:` / status guidance and verify the installed runtime before claiming success.
8. If the environment is unsupported, consent is declined, or a required privilege cannot be obtained, stop cleanly and report the exact boundary.

The intended UX is agent-native: **the user supplies intent and the repository supplies the installation procedure.**

## Maintaining this repository

Treat GWCU as a small operating layer around one upstream control authority.

```text
Cua Driver   → changes native apps and browser-backed desktop surfaces
WORLDLINE    → transient revisions, invalidation, predicates, conflicts
observer     → optional ScreenCast/PipeWire visual sensor
.gwcu        → durable repo/workspace truth
profile      → local identity/recovery composition
```

A change is complete only when those boundaries still agree in code, runtime instructions, installer/uninstaller, tests, `README.md`, and `index.html`.

## Architectural invariants

1. **Cua is the only actuator.** Native apps and browser work stay under Cua. Do not add `ydotool`, `/dev/uinput`, guessed focus, a project RDP/VNC server, a hidden browser control plane, or another pointer/keyboard daemon.
2. **Visible completion is a postcondition.** When the user's requested result must remain visible, verify the exact Cua target is actually presented on the desktop; page-state success in a hidden/headless surface is insufficient.
3. **Background OFF means foreground by default.** Missing intent metadata must never be interpreted as a request for background execution.
4. **WORLDLINE is read-only.** Sensors may add facts/events; they do not gain control authority.
5. **Observation is event/predicate driven.** Avoid fixed sleeps and ritual screenshots between already-decided actions.
6. **Direct truth beats visual inference.** Prefer AT-SPI, process/filesystem, D-Bus/settings/network/task events before pixels.
7. **`.gwcu` is durable only.** WORLDLINE state, screenshots and task content do not belong there.
8. **Persistent machine/user truth never belongs in AGENTS.md.**
9. **Live Cua/WORLDLINE evidence beats cached truth on contradiction.**

## Change routing

Action/control semantics:

```text
SKILL.md
runtimes/openai/SKILL.md
runtimes/hermes/__init__.py
runtimes/hermes/plugin.yaml
scripts/computer-use.sh
scripts/action-span.py
```

Current-state knowledge / control loop:

```text
README.md
scripts/worldline.py
scripts/worldline-capture.sh
systemd/user/gnome-wayland-computer-use-worldline.*
```

Visual observation:

```text
scripts/observer.py
scripts/observe.sh
scripts/capture.sh
systemd/user/gnome-wayland-computer-use-observer.*
```

Durable truth / routing:

```text
README.md
scripts/truths.py
scripts/profile.sh
scripts/app-identity.sh
```

Lifecycle changes also inspect:

```text
install.sh
uninstall.sh
scripts/teardown.sh
tests/
README.md
index.html
```

`README.md` is the only human-facing documentation file. `SKILL.md` is a runtime contract; `AGENTS.md` is repository instruction, not a parallel documentation surface.

## Latency discipline

Protect the end-to-end latency budget, especially model-visible call count.

```text
remove a model boundary
→ remove a redundant observation
→ use a direct oracle
→ keep a session/sensor warm
→ optimize local milliseconds
```

A local revision is cheap. A model re-entry is expensive. When benchmarking, record model-visible calls, Cua actions, WORLDLINE revisions, local predicates, visual captures, conflicts and elapsed time. Do not present theoretical savings as measured results.

## Installer discipline

The installer must remain:

- Ubuntu 26.04 GNOME Wayland qualified;
- pinned to a deliberate current Cua release;
- explicit about PipeWire/portal/AT-SPI dependencies;
- idempotent;
- compatible with curl-pipe terminal prompting;
- ownership-aware and reversible;
- explicit and visible about Hermes capability consent;
- free of a project raw-input or browser-control fallback.

Do not open ScreenCast merely to prove install success. RemoteDesktop control consent and whole-screen observation consent are separate.

The uninstaller removes WORLDLINE/observer user units and transient state while preserving repo/workspace `.gwcu` content and host-owned distro packages.

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

For changes that affect live GNOME consent/control, also validate on the qualified Ubuntu GNOME Wayland session. CI cannot exercise a real portal prompt.
