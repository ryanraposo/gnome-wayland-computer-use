# Capture latency notes

This branch separates two latency budgets:

- Hermes/native `computer_use` observation latency (`ax`, `vision`, `som`).
- Host desktop/screen helper latency (`scripts/capture.sh`).

## Policy

Use the cheapest observation that answers the next decision:

1. accessibility/tree-only for readable and targetable UI;
2. plain image for visual-only reasoning;
3. combined image + element grounding only when both are required.

A structured driver result that directly proves the requested postcondition is
sufficient verification. Avoid a duplicate post-action screenshot unless the
UI structure changed, targeting references became stale, or visual evidence is
actually required.

Installed standalone web apps keep their own app identity when desktop/window
metadata distinguishes them from the browser engine underneath them.

## Host capture targets

`capture.sh --timing` emits `capture_elapsed_ms=N` on stderr.

The compatibility screenshot rungs should return as soon as the screenshot
file exists. The regression guard requires mocked immediate captures to finish
in under one second, specifically preventing the former fixed 1.5 second waits
from returning.

For real-machine measurement, collect repeated timings separately for desktop
and screen capture and compare median and p95. Do the same for Hermes `ax`,
`vision`, and `som` captures so driver/runtime latency is not conflated with the
host helper.
