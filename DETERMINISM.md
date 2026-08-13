# Deterministic computer use

Version 2.3 keeps the four-plane architecture and moves routine routing facts out
of model deliberation and into software.

> The agent decides intent. The operating layer decides mechanics.

## Hot path

A named target does not trigger updates, diagnosis, app enumeration, or a
whole-screen screenshot. The normal trajectory is:

```text
one Cua target state
→ AX when semantics ground the control
→ PX from the same returned screenshot when they do not
→ consume Cua effect/escalation
→ foreground only when the runtime requires it
→ verify only at a real decision boundary
```

Cua owns target delivery, foreground verification, and WinRects. This project
does not duplicate those decisions.

## Project machine contracts

| Surface | Schema | Purpose |
|---|---|---|
| `observe.sh --machine` | `gwcu.observe.v1` | whole-screen observation verdict |
| `observer.py client ...` | `gwcu.observer.v1` | warm ScreenCast broker IPC |
| `app-identity.sh --resolve --machine` | `gwcu.identity.v1` | resolved / ambiguous / missing launcher identity |
| `diagnose.sh --machine` | `gwcu.diagnose.v1` | one atomic four-plane diagnostic |
| `profile.sh read|refresh --machine` | `gwcu.profile.v1` | passive session capability state |
| `ownership.json` | `gwcu.ownership.v1` | teardown ownership, separate from capability state |

Coarse exit classes are intentionally small:

```text
0   operation completed; JSON is authoritative
2   caller/usage error
10  route miss / explicit ambiguity
20  terminal user or policy condition
30  capability unavailable or pending
40  transient technical failure
50  internal/protocol failure
```

Fine-grained behavior lives in JSON `code`, `retryable`, `terminal`, and `next`.

## Persistent observation

`gnome-wayland-computer-use-observer.socket` is enabled in the user session.
Socket activation does not create a ScreenCast session. The broker starts only
when a client connects, and `status` itself does not request screen access.

On the first real capture it creates one XDG ScreenCast session, opens the
portal-scoped PipeWire remote, and keeps a raw GStreamer frame stream warm for a
short task burst. The default capture returns the first frame produced after the
request. The broker closes the live portal/PipeWire session after idle timeout;
the socket remains available.

ScreenCast v6 `pipewire-serial` is preferred through `target-object` when the
installed `pipewiresrc` supports it. Older portals/plugins retain the numeric
node-id compatibility route.

The existing `capture.sh` remains independent direct ScreenCast recovery. The
broker is an optimization, never a single point of failure.

Portal cancellation is terminal for that capture request. No Screenshot or
synthetic-key permission UI is opened behind the user's cancellation.

## Ubuntu 26.04 foundation

Normal Ubuntu 26.04 GNOME already supplies a PipeWire/WirePlumber/portal-era
desktop. Installation is verify-first and repairs incomplete hosts from Ubuntu
packages:

- `pipewire`
- `wireplumber`
- `xdg-desktop-portal`
- `xdg-desktop-portal-gnome`
- `gstreamer1.0-pipewire`
- `gstreamer1.0-plugins-base`
- `gstreamer1.0-plugins-good`
- `gstreamer1.0-tools`
- `python3-gi`
- `python3-gst-1.0`
- GStreamer/GdkPixbuf GIR packages when their imports are absent
- `at-spi2-core` when the semantic bus launcher is absent
- `ydotool` only for recovery

`pipewire-pulse` is an audio compatibility service, not a ScreenCast readiness
gate, so computer-use observation does not install it merely for capture.

For the Hermes profile, Cua Driver is installed from Cua's official installer
when absent. `winrects@cua` is provisioned only through Cua's packaged
`wayland-helper/install.sh`.

## Ownership

Capability state and ownership are deliberately separate. `profile.json` can be
regenerated. `ownership.json` records project-created units/resources.

The legacy `cua-winrects-managed` marker remains authoritative during migration:
absence of that marker can never make a pre-existing WinRects installation
project-owned.

Teardown removes project observer/runtime state but preserves distro foundation
packages and unrelated/pre-existing GNOME extensions.

## Performance constitution

Until a controlled GNOME 50 host records real distributions, latency numbers are
budgets rather than claims:

```text
successful known-target task:
  0 update checks
  0 diagnose calls
  0 app/window enumeration unless identity is unresolved
  0 whole-screen captures when target-level state is sufficient
  0 repeated identical failed rungs

whole-screen task burst:
  1 portal/PipeWire session
  N broker frame requests

warm 1080p broker target:
  p50 ≤ 75 ms
  p95 ≤ 150 ms
```

The release benchmark must also count model/tool round trips, whole-screen
captures, foreground activations, and repeated failed routes. Faster pixels
without fewer decisions is not a successful determinism release.
