# Mutter / Ubuntu GNOME Wayland acceptance matrix

Offline regression tests (`python3 tests/mutter-presentation.py`, included in `tests/run.sh`) cover exact window identity despite sticky/MRU reordering, fail-closed focus/geometry validation, current-geometry sampling after monitor movement, and rejecting lost focus.

The live acceptance lane remains a **physical GNOME Wayland desktop test**, not an assertion about headless fixtures:

| Scenario | Expected proof | Regression |
| --- | --- | --- |
| GNOME 50 + Ubuntu 26.04 Mutter package update | After Alt+Tab with pointer over another window, exact target is focused before Cua input | Focus does not follow pointer or remain stale |
| Maximized window moved between displays | Re-present and sample two stable, matching rectangles before coordinate input | Old monitor coordinates never accepted |
| Mutter 51.1 sticky-window / MRU ordering | Exact `(pid, window_id)` is stable across ordering changes | Never act on a window chosen by list index/title |
| Mutter 51.1 monitor/workspace reconfiguration | Reacquire live window geometry and focus | No coordinate operation based on old placement |
| Mutter 51.1 Wayland → Xwayland and reverse drag/drop | Target data delivered; source/target unchanged; receipt follows new visual/semantic evidence | Do not infer drag success from pointer-up alone |
| Power-saving / frame-clock throttle | Record dispatch, semantic advancement, PipeWire arrival as separate times | Slow frame is `observation-delayed`, not automatically `action-failed` |

A desktop harness should report the active compositor session, exact Mutter/gnome-shell package versions, monitor layout, Cua helper API, and PipeWire stream generation. Never label the physical cases as passed from offline fixtures. GNOME 51 upstream behavior must not be conflated with Ubuntu 26.04's packaged GNOME 50.
