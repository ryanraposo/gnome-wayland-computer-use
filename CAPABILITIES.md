# Capability Map

## Ownership

| Capability | Authority | Ubuntu/GNOME substrate | GWCU role |
|---|---|---|---|
| Target discovery/state | Cua Driver | GNOME/AT-SPI/Mutter | instruct agent to use Cua directly |
| Semantic actions | Cua Driver | AT-SPI | provision accessibility; do not reimplement actions |
| Target pixels | Cua Driver | Cua platform capture | none |
| Window geometry / exact activation | Cua Driver | `winrects@cua` + Mutter | install Cua's packaged helper |
| Foreground input | Cua Driver | RemoteDesktop → EIS/libei | establish one-time portal consent during install |
| Verification/refusal | Cua Driver | platform-specific | consume structured results |
| Cua readiness | Cua Driver | stable `health_report` | transport, do not reconstruct |
| Whole visible screen | GWCU | ScreenCast + PipeWire | private warm broker + Screenshot fallback |
| App identity | GWCU | desktop entries | deterministic resolver |
| Durable local truth | GWCU | repo/workspace `.gwcu` | compact acceleration surface; live Cua wins |
| Installed-system readiness | GWCU + Cua | session + observation + Cua health | one compressed verdict |
| Hermes slash commands | Hermes plugin API | user plugin | `/computer-use` status/managed/truths/consent/doctor |
| User choices | Hermes `clarify` / installer tty | user | explicit decisions only |

## `.gwcu` truth boundary

Persistent machine/workspace state never belongs in `AGENTS.md`.

`.gwcu` is a repo/workspace-scoped file with schema `gwcu.truths.v1`:

```text
observed       generated low-churn environment facts
capabilities   generated compact capability conclusions
calibration    generated learned measurements/mappings
preferences    user-authored behavior choices; preserved
apps           generated stable launcher/PWA identity
```

Scope:

```text
GWCU_SCOPE_ROOT override
→ Git worktree root, when inside Git
→ nearest ancestor containing .gwcu, outside Git
→ current working directory
```

Git repositories are always isolated to their own root, including repositories
nested inside a broader non-Git workspace. Managed Git scopes establish
`/.gwcu` in the root `.gitignore` before the file is created. Non-Git scopes use
the nearest existing ancestor `.gwcu` and need no ignore mutation.

Generated truth can be rebuilt. Preferences and unknown top-level extension
keys survive generated-truth regeneration. Live evidence outranks all stored
generated truth.

## Explicitly out of architecture

GWCU does not install or own:

- `/dev/uinput` policy;
- `ydotool` / `ydotoold` control;
- `input` group membership;
- a project-managed `cua-driver serve` daemon;
- an RDP/VNC server;
- a private WinRects client;
- toolkit-specific focus guessing;
- machine/display truth embedded in prompt prose.

## RemoteDesktop boundary

GNOME's `org.freedesktop.portal.RemoteDesktop` is used as the local
compositor-approved input API. Cua requests pointer + keyboard, receives an
EIS/libei session, and may persist GNOME's revocable restore token.

GWCU's bootstrap uses one Cua desktop `move_cursor` action to establish that
session: no click and no key. `/computer-use consent` and `portal-control.py
--status` surface the contract.

## Installer completion states

| State | Meaning |
|---|---|
| `READY` | native substrate, control consent, observer, Cua health, and GNOME helper are ready |
| `READY EXCEPT GNOME HELPER RELOAD` | control consent/health are ready; updated WinRects needs one Shell reload/sign-out |
| failure | unresolved dependency, consent, Cua health, or observer problem |

There is no successful “mostly installed, diagnose it yourself” state.
