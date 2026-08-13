# Capability Map

## Ownership

| Capability | Authority | Ubuntu/GNOME substrate | Project role |
|---|---|---|---|
| Target discovery/state | Cua Driver | GNOME/AT-SPI/Mutter | instruct agent to use Cua directly |
| Semantic actions | Cua Driver | AT-SPI | provision accessibility; never reimplement action mechanics |
| Target pixels | Cua Driver | Cua platform capture | none |
| Window geometry / exact activation | Cua Driver | `winrects@cua` + Mutter | invoke only Cua's packaged helper installer |
| Foreground input | Cua Driver | RemoteDesktop + EIS/libei | qualify portal substrate |
| Verification/refusal | Cua Driver | platform-specific | consume structured result |
| Cua readiness | Cua Driver | stable `health_report` | transport structured result; do not reconstruct it |
| Whole visible screen | GWCU | XDG ScreenCast + PipeWire | private warm broker + Screenshot portal fallback |
| App identity | GWCU | desktop entries | deterministic launcher/PWA resolver |
| Project routing memory | GWCU | project-root `AGENTS.md` | bounded regex-addressable stable identity cache; live Cua wins |
| Installed-system readiness | GWCU + Cua | session + observation + Cua health + WinRects | one compressed verdict |
| Real user choice | Hermes when available | `clarify` | structured options; parent session owns the decision |
| One-off mechanical fan-out | Hermes when available | `execute_code` | collapse tool/program sequences into one inference turn |
| Independent reasoning | Hermes when available | `delegate_task` | compact delegated result; no interactive portal/user decisions |
| Bounded long shell work | Hermes when available | managed terminal background | completion notification instead of polling turns |

## Explicitly out of architecture

The project does not install or own:

- `/dev/uinput` policy;
- `ydotool` or `ydotoold` as a control path;
- `input` group membership;
- a project-managed `cua-driver serve` daemon;
- a private WinRects implementation or D-Bus client;
- toolkit-specific focus guessing.

A Cua structured refusal is a capability boundary, not a request to construct a
shadow input stack.

## Project-memory boundary

The managed project block is an acceleration cache, not general memory:

```text
<!-- gwcu:desktop-truths:v1:start -->
<!-- gwcu:app:v1 {compact stable identity JSON} -->
<!-- gwcu:desktop-truths:v1:end -->
```

It is bounded, timestamp-free, comment-safe, and limited to low-churn app
identity. User-authored AGENTS content outside the markers is preserved. Live
Cua state always outranks remembered identity.

## Whole-screen observation

```text
socket-activated warm ScreenCast broker
        ↓ technical broker/service failure only
one-process XDG Screenshot portal fallback
```

Portal cancellation is terminal for the request. Whole-screen observation is
used only for explicit screen requests or discovery that target-scoped Cua state
cannot satisfy.

## Health boundary

Cua's `health_report` is the stable downstream readiness contract. GWCU uses a
short-lived direct stdio MCP session and preserves the returned structured
report under `gwcu.cua-health.v1`. `cua-driver doctor --json` is retained as
excellent diagnostic/install evidence, but not as a replacement health model.

## Installer completion states

| State | Meaning |
|---|---|
| `READY` | Ubuntu substrate, observer, Cua health and active GNOME helper are ready |
| `READY EXCEPT GNOME HELPER RELOAD` | control/observation are installed; one GNOME reload/sign-in is needed for new helper code |
| failure | an unresolved dependency, doctor/health failure, or observer problem remains |

There is no successful “mostly installed, diagnose it yourself” state.
