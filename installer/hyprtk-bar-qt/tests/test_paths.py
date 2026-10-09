"""Unit tests for the config-path helpers / first-run migration (no Qt)."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import paths  # noqa: E402


class SeedFromGtk(unittest.TestCase):
    def test_copies_when_qt_missing(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            gtk = Path(tmp) / "gtk.json"
            gtk.write_text('{"position": "top", "layout": {"left": ["clock"]}}')
            qt = Path(tmp) / "sub" / "qt.json"
            with mock.patch.object(paths, "GTK_CONFIG", gtk):
                self.assertTrue(paths.seed_from_gtk(qt))
            self.assertEqual(json.loads(qt.read_text())["layout"], {"left": ["clock"]})

    def test_migrates_legacy_keeps_qt_only(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            gtk = Path(tmp) / "gtk.json"
            gtk.write_text(json.dumps({
                "position": "top",
                "opacity": 0.92,
                "animations": {"mode": "high", "speed": 15},
                "layout": {"left": ["workspaces"]},
            }))
            qt = Path(tmp) / "qt.json"
            qt.write_text(json.dumps({
                "clockFormat": "HH:mm",
                "themeBackground": "#123456",
                "opacity": -1,          # legacy override -> GTK wins
                "animations": {"speed": 9},  # legacy -> GTK schema wins
            }))
            with mock.patch.object(paths, "GTK_CONFIG", gtk):
                self.assertTrue(paths.seed_from_gtk(qt))
            out = json.loads(qt.read_text())
            self.assertEqual(out["position"], "top")            # from GTK
            self.assertEqual(out["layout"], {"left": ["workspaces"]})
            self.assertEqual(out["opacity"], 0.92)              # GTK wins
            self.assertEqual(out["animations"], {"mode": "high", "speed": 15})
            self.assertEqual(out["clockFormat"], "HH:mm")       # Qt-only kept
            self.assertEqual(out["themeBackground"], "#123456")  # Qt-only kept

    def test_skips_already_migrated(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            gtk = Path(tmp) / "gtk.json"
            gtk.write_text('{"position": "top"}')
            qt = Path(tmp) / "qt.json"
            qt.write_text('{"position": "bottom", "clockFormat": "HH:mm"}')
            with mock.patch.object(paths, "GTK_CONFIG", gtk):
                self.assertFalse(paths.seed_from_gtk(qt))
            self.assertEqual(json.loads(qt.read_text())["position"], "bottom")

    def test_no_gtk_config(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            qt = Path(tmp) / "qt.json"
            with mock.patch.object(paths, "GTK_CONFIG", Path(tmp) / "missing.json"):
                self.assertFalse(paths.seed_from_gtk(qt))
            self.assertFalse(qt.exists())


if __name__ == "__main__":
    unittest.main()
