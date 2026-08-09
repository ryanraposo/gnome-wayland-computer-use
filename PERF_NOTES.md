# Computer-use latency notes

This work separates the latency budget instead of treating every pause as a
screenshot problem.

## Budgets

1. **Startup/routing** — skill first-use work and update checks.
2. **Target discovery** — app/window lookup and browser-vs-installed-web-app identity.
3. **Observation** — native `computer_use` AX, vision, and SOM latency.
4. **Action loop** — tool/model round-trips spent on click, type, shortcuts,
   values, scrolling, and waits.
5. **Verification** — duplicate observations after already verified actions.
6. **Host capture** — `scripts/capture.sh` desktop/screen helper latency.
7. **Recovery** — service restart and readiness polling after a backend failure.

## Fast-path policy

- First-use update checks are cache-only; the computer-use hot path never waits
  on DNS or HTTP.
- Resolve an app/window once and reuse it until evidence invalidates the target.
- Installed standalone web apps keep their own identity. The launcher resolver
  understands direct and wrapped browser commands, including Flatpak-style
  launchers, `--app-id`, `--app`, desktop IDs, and `StartupWMClass`.
- AX is the default when text/roles/state are sufficient. Vision is for pixels;
  SOM is for pixels plus element grounding.
- Keep deterministic semantic input together: complete typing, complete
  shortcuts, direct value setting, and coupled click → type / type → submit
  spans when the next input does not depend on newly rendered state.
- Treat structured `confirmed` + `verified` read-back as verification when it
  proves the requested postcondition.
- Obtain fresh evidence at real decision boundaries: navigation, dialogs,
  material list changes, stale targets, canvas/visual ambiguity, focus
  escalation, or when the next action depends on new UI state.
- Use `wait` only for genuine asynchronous transitions without a completion
  signal; start short and extend from evidence.

## Host capture

`capture.sh --timing` emits `capture_elapsed_ms=N` on stderr while preserving
normal stdout/media behavior.

Compatibility screenshot paths poll for readiness instead of imposing the old
fixed 1.5 second screenshot sleep. Desktop compatibility capture also polls
compositor restoration instead of fixed animation sleeps.

The regression guard requires mocked immediate screen and desktop compatibility
captures to remain below one second. This ceiling is intentionally loose enough
for shared CI while preventing reintroduction of multi-second fixed waits.

## Recovery

Managed `cua-driver` and `ydotoold` services use a 250 ms restart delay instead
of two seconds. Installer readiness probes use 100 ms polling rather than one
second polling.

## Final integration guard

The published landing page, runtime skills, installer, helper scripts, UX
contract, and tests are expected to describe the same latency model. CI guards
that contract, including browser vs PWA identity and wrapped/Flatpak launchers.

On the final integration CI run, mocked hot paths measured:

- cache-only first-use update check: **9 ms**;
- immediate screen fallback: **34 ms**;
- desktop compatibility fallback: **284 ms**.

These are regression-fixture timings, not claims about a real GNOME session.
They prove that the repository itself no longer injects the former multi-second
fixed waits into those paths.

## Real-machine measurement

Measure native Hermes/cua-driver behavior separately from the host helper:

- repeated `ax` captures;
- repeated `vision` captures;
- repeated `som` captures;
- representative semantic actions and verified action spans;
- `capture.sh --timing --screen`;
- `capture.sh --timing --desktop`.

Record median/p50, p95, and worst. If native image capture remains slow while AX
and host capture are fast, investigate cua-driver/portal/image encoding rather
than adding sleeps or another screenshot stack.

The goal is a computer-use loop that spends latency on meaningful decisions,
not on redundant discovery, network checks, screenshots, tiny input calls,
ceremonial verification, or recovery timers.
