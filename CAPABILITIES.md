# Capability Map

## Ownership

| Capability | Authority | Ubuntu/GNOME substrate | Project role |
|---|---|---|---|
| Target discovery/state | Cua Driver | GNOME/AT-SPI/Mutter | instruct the agent to use Cua directly |
| Semantic actions | Cua Driver | AT-SPI | provision accessibility; do not reimplement actions |
| Target pixels | Cua Driver | Cua platform capture | none |
| Window geometry | Cua Driver | `winrects@cua` on GNOME | invoke Cua's packaged helper installer |
| Exact activation | Cua Driver | `winrects@cua` + Mutter | none |
| Foreground input | Cua Driver | portal/libei on GNOME | none |
| Verification/refusal | Cua Driver | platform-specific | consume the structured result |
| Whole visible screen | GWCU | XDG ScreenCast + PipeWire | broker, direct portal fallback, machine envelope |
| App identity | GWCU | desktop entries | deterministic resolver |
| Host readiness | GWCU + Cua | session + observation + Cua doctor | one compressed verdict |

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

## Whole-screen observation

Normal order:

```text
socket-activated warm ScreenCast broker
        ↓ technical broker/service failure only
one-process XDG Screenshot portal fallback
```

Portal cancellation is terminal for the request. Whole-screen observation is
used only for explicit screen requests or discovery that target-scoped Cua state
cannot satisfy.

## Installer completion states

| State | Meaning |
|---|---|
| `READY` | Ubuntu observation substrate, observer, Cua doctor, and active GNOME helper are ready |
| `READY EXCEPT GNOME PRECISION` | new/updated Cua helper is on disk; one GNOME sign-out/in loads it |
| failure | installer detected an unresolved dependency or Cua/observer problem and exits non-zero |

There is no successful “mostly installed, diagnose it yourself” state.
