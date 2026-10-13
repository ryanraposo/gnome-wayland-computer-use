#!/usr/bin/env python3
"""Offline compositor-contract regressions for Mutter 50/51 and Ubuntu 26."""
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "gwcu_present_window",
    Path(__file__).resolve().parents[1] / "scripts/present-window.py",
)
presentation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(presentation)


def window(*, window_id=42, pid=7, x=0, focused=True, monitor="HDMI-A-1"):
    return {
        "id": window_id, "pid": pid, "x": x, "y": 0,
        "w": 800, "h": 600, "focused": focused,
        "visible": True, "minimized": False,
        "monitor": monitor,
    }


class CompositorPresentationTests(unittest.TestCase):
    def test_mru_or_sticky_reorder_never_changes_target(self):
        windows = [window(window_id=99, pid=8), window(), window(window_id=100)]
        self.assertEqual(presentation.exact_window(windows, 7, 42)["id"], 42)
        self.assertIsNone(presentation.exact_window(windows, 7, 43))
        self.assertIsNone(presentation.exact_window(windows + [window()], 7, 42))

    def test_monitor_reassignment_waits_for_stable_live_geometry(self):
        frames = [
            [window(x=0)],
            [window(x=0)],
            [window(x=1920, monitor="DP-1")],
            [window(x=1920, monitor="DP-1")],
        ]
        with (
            patch.object(presentation, "trusted_shell_owner", return_value=(":1.3", 8)),
            patch.object(presentation, "rects", side_effect=frames) as reads,
            patch.object(presentation, "gdbus", return_value="(true,)"),
            patch.object(presentation.time, "sleep"),
        ):
            receipt = presentation.present(7, 42, 500)
        self.assertTrue(receipt["ok"], receipt)
        self.assertEqual(receipt["window"]["x"], 1920)
        self.assertEqual(receipt["window"]["monitor"], "DP-1")
        self.assertGreaterEqual(reads.call_count, 4)
        self.assertGreater(receipt["observed_at_monotonic_ns"], 0)

    def test_focus_outside_target_is_not_proof(self):
        self.assertFalse(presentation.presented(window(focused=False)))
        self.assertFalse(presentation.presented({**window(), "w": 0}))
        self.assertFalse(presentation.presented({**window(), "x": float("nan")}))
        self.assertTrue(presentation.presented(window(x=-100)))

    def test_verify_rechecks_compositor_instead_of_reusing_old_proof(self):
        with (
            patch.object(presentation, "trusted_shell_owner", return_value=(":1.3", 8)),
            patch.object(presentation, "rects", return_value=[window(focused=False)]),
        ):
            receipt = presentation.verify(7, 42)
        self.assertFalse(receipt["ok"])
        self.assertEqual(receipt["code"], "not_presented")


if __name__ == "__main__":
    unittest.main()
