"""Unit tests for the bar-config editor (no Qt)."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import barsettings  # noqa: E402


class DeepMerge(unittest.TestCase):
    def test_nested_merge(self) -> None:
        base = {"height": 38, "arcmenu": {"radius": 140, "enabled": True}}
        barsettings.deep_merge(base, {"arcmenu": {"radius": 200}})
        self.assertEqual(base["arcmenu"]["radius"], 200)
        self.assertTrue(base["arcmenu"]["enabled"])
        self.assertEqual(base["height"], 38)

    def test_scalar_overwrites(self) -> None:
        base = {"height": 38}
        barsettings.deep_merge(base, {"height": 42})
        self.assertEqual(base["height"], 42)


class Apply(unittest.TestCase):
    def test_apply_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text('{"height": 38, "layout": {"right": ["clock"]}}')
            self.assertTrue(barsettings.apply({"gap_in": 4, "layout": {"left": ["workspaces"]}}, path))
            data = json.loads(path.read_text())
            self.assertEqual(data["gap_in"], 4)
            self.assertEqual(data["layout"]["left"], ["workspaces"])
            self.assertEqual(data["layout"]["right"], ["clock"])  # preserved
            self.assertEqual(data["height"], 38)

    def test_apply_creates_file(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            self.assertTrue(barsettings.apply({"opacity": 0.8}, path))
            self.assertEqual(json.loads(path.read_text())["opacity"], 0.8)


if __name__ == "__main__":
    unittest.main()
