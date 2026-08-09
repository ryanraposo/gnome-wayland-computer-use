# Computer-use latency notes

This work separates the latency budget instead of treating every pause as a
screenshot problem.

## Budgets

1. **Startup/routing** — skill first-use work and update checks.
2. **Target discovery** — app/window lookup and browser-vs-installed-web-app identity.
3. **Observation** — native `computer_use` AX, vision, and SOM latency.
4. **Action loop** — tool/model round-trips for click, type, key, set-value,
   scroll, drag, and focus delivery.
5. **Verification** — redundant post-action observation versus structured
   driver read-back.
6. **Host capture** — `scripts/capture.sh` desktop/screen routing.
7. **Recovery** — service restart and fallback delay after a real failure.

## Policy

Use the cheapest evidence that answers the next decision:

1. accessibility/tree-only for readable and targetable UI;
2. plain image for visual-only reasoning;
3. combined image + element grounding only when both are required.

Resolve the target once and reuse it until evidence invalidates it. Installed
standalone web apps keep their own identity when desktop/window metadata or
launcher flags distinguish them from the browser engine underneath them.
`scripts/app-identity.sh` provides a cached launcher lookup for browser/PWA
ambiguity without spending a screenshot.

A structured driver result that directly proves the requested postcondition is
sufficient verification. Avoid a duplicate post-action screenshot unless UI
structure changed, targeting references became stale, visual evidence is
actually required, or the next action depends on newly rendered state.

Execute deterministic semantic action spans instead of manufacturing model/tool
round-trips: one full-text typing action, one hotkey, direct semantic value
selection, useful scroll increments, and no intermediate capture between
confirmed coupled actions when the next action does not depend on changed UI.

First-use update checks are cache-only. Explicit update checks can refresh the
cache. Managed cua-driver/ydotool services use short restart delays so a real
backend failure does not impose an avoidable multi-second recovery penalty.

## Host capture targets

`capture.sh --timing` emits `capture_elapsed_ms=N` on stderr.

The compatibility screenshot rungs return as soon as the screenshot file and
required compositor state are ready. Regression guards require mocked immediate
captures to finish in under one second, preventing the former fixed 1.5 second
waits from returning.

## Measurement

Do not combine unlike costs into one number. Measure repeated warm runs and
report median/p50 and p95 separately for:

- first-use routing with a cold/no update cache;
- app/window discovery and cached installed-web-app identity lookup;
- native `ax`, `vision`, and `som` observations;
- representative semantic actions and a short form-filling sequence;
- desktop and screen helper capture;
- backend restart/recovery when deliberately exercised.

The important user-facing metric is a representative task span: resolve target,
inspect, act, and prove the requested result. A faster screenshot is useful; a
workflow that avoids unnecessary screenshots, discovery calls, waits, and model
round-trips is the larger win.
