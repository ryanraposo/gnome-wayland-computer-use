# Capability Map

## Ownership

| Capability | Authority | Ubuntu/GNOME substrate | Project role |
|---|---|---|---|
| Target discovery/state | Cua Driver | GNOME/AT-SPI/Mutter | instruct the agent to use Cua directly |
| Semantic actions | Cua Driver | AT-SPI | provision accessibility; do not reimplement actions |
| Target pixels | Cua Driver | Cua platform capture | none |
| Window geometry / exact activation | Cua Driver | `winrects@cua` + Mutter | install Cua's packaged helper |
| Foreground input | Cua Driver | RemoteDesktop → EIS/libei | establish one-time portal consent during install |
| Verification/refusal | Cua Driver | platform-specific | consume structured results |
| Cua readiness | Cua Driver | stable `health_report` | transport, do not reconstruct |
| Whole visible screen | GWCU | ScreenCast + PipeWire | private warm broker + Screenshot fallback |
| App identity | GWCU | desktop entries | deterministic resolver |
| Stable project routing truth | GWCU | project `AGENTS.md` | bounded optional acceleration cache |
| Installed-system readiness | GWCU + Cua | session + observation + Cua health | one compressed verdict |
| Hermes slash commands | Hermes plugin API | user plugin | `/computer-use` status/managed/consent/doctor |
| User choices | Hermes `clarify` / installer tty | user | explicit decisions only |

## Explicitly out of architecture

GWCU does not install or own:

- `/dev/uinput` policy;
- `ydotool` / `ydotoold` control;
- `input` group membership;
- a project-managed `cua-driver serve` daemon;
- an RDP/VNC server;
- a private WinRects client;
- toolkit-specific focus guessing.

## RemoteDesktop boundary

GNOME's `org.freedesktop.portal.RemoteDesktop` is used as the local
compositor-approved input API. Cua requests pointer + keyboard, receives an
EIS/libei session, and may persist GNOME's revocable restore token.

GWCU's bootstrap uses one Cua desktop `move_cursor` action to establish that
session: no click and no key. `/computer-use consent` and `portal-control.py
--status` surface the contract and check for retired GWCU raw-input artifacts.

## Managed project truth boundary

The managed `AGENTS.md` block stores low-churn identity only, max 24 entries.
Live Cua state has higher authority. Uninstall never searches arbitrary user
repositories to remove blocks already written there.

## Installer completion states

| State | Meaning |
|---|---|
| `READY` | native substrate, control consent, observer, Cua health, and GNOME helper are ready |
| `READY EXCEPT GNOME HELPER RELOAD` | control consent/health are ready; updated WinRects needs one Shell reload/sign-out |
| failure | unresolved dependency, consent, Cua health, or observer problem |

There is no successful “mostly installed, diagnose it yourself” state.
