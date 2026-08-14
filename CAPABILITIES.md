# Capabilities

GWCU is an operating layer around Cua Driver for Ubuntu 26.04 GNOME Wayland.

## Responsibilities

| Surface | Owns | Does not own |
|---|---|---|
| **Cua Driver** | semantic/pixel targeting, geometry, activation, input, verification, refusals | durable workspace memory |
| **WORLDLINE** | transient facts, revisions, invalidation, predicates, conflict/wake signals | input injection or intent reasoning |
| **Observer** | optional whole-screen ScreenCast/PipeWire frames | desktop control |
| **`.gwcu`** | durable low-churn repo/workspace truth | transient UI state |
| **Profile/router** | deterministic app/PWA identity and host recovery composition | live control |

## WORLDLINE inputs

Current v1 can ingest:

- AT-SPI focus/object/window events through Python GI;
- task-specific events over the private Unix socket;
- session/desktop facts;
- GNOME settings;
- NetworkManager state;
- requested process facts from `/proc`;
- requested filesystem facts;
- fresh observer frames when visual evidence is requested.

WORLDLINE turns those sources into one revision vocabulary:

```text
changed
invalidated
preserved
predicates_satisfied
woken
conflicts
```

## Desktop control

Cua is the sole actuator.

GNOME Wayland control follows:

```text
Cua → org.freedesktop.portal.RemoteDesktop → EIS → libei
```

No X11 or XWayland session is required.

GWCU does not install a raw-input daemon, project udev input rule or RDP/VNC
server.

## Visual observation

Whole-screen observation follows:

```text
GWCU observer
→ org.freedesktop.portal.ScreenCast
→ PipeWire
→ frame
```

It is independently consented and independently socket activated. WORLDLINE can
request it, but does not require a ScreenCast session for semantic/direct
revisions.

## Action composition

`computer-use.sh span` keeps one Cua MCP session open for a predetermined
sequence of actions. The span stops at the first Cua failure/refusal/transport
boundary.

`worldline-capture.sh` provides a deterministic postcondition surface around
runtime state.

Together they let a caller collapse mechanics without replacing Cua.

## Durable routing

`profile.sh route` performs:

```text
.gwcu lookup
→ local app/PWA resolver only on miss
→ optional stable writeback
→ one gwcu.route.v1 result
```

`profile.sh recover` composes cached host state and diagnosis behind one call.

## Installation

The installer owns one-time integration:

- explicit Ubuntu portal/PipeWire/AT-SPI dependencies;
- pinned Cua qualification;
- Cua GNOME helper;
- RemoteDesktop permission bootstrap;
- WORLDLINE + observer user units;
- skill/runtime deployment;
- optional Hermes command plugin;
- reversible ownership metadata.

It does not take ownership of Ubuntu's host packages merely because it repaired
them.
