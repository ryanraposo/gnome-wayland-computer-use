#!/usr/bin/env python3
"""Offline GNOME 50+ admission-contract regressions."""
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location(
    "gwcu_present_window",
    Path(__file__).resolve().parents[1] / "scripts/present-window.py",
)
presentation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(presentation)


class WorldlineAdmissionTests(unittest.TestCase):
    def test_exact_compositor_identity_and_verified_foreground(self):
        result = presentation.self_test()
        self.assertTrue(result["ok"], result)
        self.assertIn("worldline_exact_pid_compositor_id_binding", result["checks"])

    def test_no_shell_activation_surface(self):
        source = (Path(__file__).resolve().parents[1] / "scripts/present-window.py").read_text()
        self.assertNotIn("org.cua.WinRects", source)
        self.assertNotIn(".Activate(", source)
        self.assertIn("def worldline_query", source)

    def test_semantic_or_unverified_frame_cannot_admit_coordinate_input(self):
        row = {
            "pid": 42, "compositor_id": 9, "compositor_verified": False,
            "geometry_source": "at-spi2", "focused": True, "visible": True,
            "minimized": False, "frame": {"x": 0, "y": 0, "width": 100, "height": 100},
        }
        self.assertIsNone(presentation.exact_window({"items": [row]}, 42, 9))


if __name__ == "__main__":
    unittest.main()
