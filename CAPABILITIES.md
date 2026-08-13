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
| Cua readiness | Cua Driver | stable `health_report` MCP contract | transport the report verbatim; do not reconstruct it |
| Whole visible screen | GWCU | XDG ScreenCast + PipeWire | broker, direct portal fallback, machine envelope |
| App identity | GWCU | desktop entries | deterministic resolver |
| Installed-system readiness | GWCU + Cua | session + observation + Cua health + WinRects session state | one compressed verdict |

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

## Health boundary

Cua's `health_report` is the stable downstream readiness contract. GWCU talks to
it through a short-lived direct stdio MCP session and preserves the returned
`schema_version`, `overall`, and checks under `gwcu.cua-health.v1`.

`cua-driver doctor --json` is also recorded because it is excellent diagnostic
evidence, but its warning-tolerant exit status is not treated as a full health
boolean.

## Installer completion states

| State | Meaning |
|---|---|
| `READY` | Ubuntu observation substrate, observer, Cua `health_report=ok`, and active GNOME helper are ready |
| `READY EXCEPT GNOME PRECISION` | Cua health and observation are ready; new/updated WinRects is on disk and one GNOME sign-out/in loads it |
| failure | installer detected an unresolved dependency, degraded/failed Cua health, or observer problem and exits non-zero |

There is no successful “mostly installed, diagnose it yourself” state.
