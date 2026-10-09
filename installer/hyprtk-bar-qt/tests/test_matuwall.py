"""Unit tests for the matuwall TOML read/write backend (no Qt)."""

from __future__ import annotations

import os
import sys
import tempfile
import tomllib
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import matuwall  # noqa: E402


class Toml(unittest.TestCase):
    def test_roundtrip(self) -> None:
        cfg = {
            "general": {"directory": "~/Pictures/Wallpapers", "backend": "awww"},
            "window": {"preview": True, "margin": 34},
            "hooks": {"on_apply": ["foo", "bar"]},
        }
        self.assertEqual(tomllib.loads(matuwall.toml_dumps(cfg)), cfg)

    def test_value_types(self) -> None:
        self.assertEqual(matuwall.toml_value(True), "true")
        self.assertEqual(matuwall.toml_value(5), "5")
        self.assertEqual(matuwall.toml_value(["a", "b"]), '["a", "b"]')
        self.assertEqual(matuwall.toml_value("x"), '"x"')


class Accessors(unittest.TestCase):
    def test_get_set_nested(self) -> None:
        cfg = {}
        matuwall.cfg_set(cfg, "backend.awww", "args", ["--x"])
        self.assertEqual(matuwall.cfg_get(cfg, "backend.awww", "args"), ["--x"])
        self.assertIsNone(matuwall.cfg_get(cfg, "nope", "x"))


class Template(unittest.TestCase):
    def test_replacements_skip_colors(self) -> None:
        cfg = {"colors": {"tile": "#000"}, "window": {"margin": 34}}
        rep = matuwall.template_replacements(cfg)
        self.assertIn(("window", "margin"), rep)
        self.assertNotIn(("colors", "tile"), rep)

    def test_update_preserves_other_lines(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            tpl = Path(tmp) / "matuwall-config.toml"
            tpl.write_text("[window]\nmargin = 10\nradius = 40\n")
            with mock.patch.object(matuwall, "MATUWALL_TEMPLATE", tpl):
                matuwall.update_template({("window", "margin"): "34"})
            text = tpl.read_text()
            self.assertIn("margin = 34", text)
            self.assertIn("radius = 40", text)


if __name__ == "__main__":
    unittest.main()
