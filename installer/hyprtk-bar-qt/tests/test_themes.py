"""Unit tests for the toolkit-free theme importer + themer CLI (no Qt)."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import theme_import, themes  # noqa: E402

SAMPLE_CSS = """
@define-color accent #ff00ff;
window#waybar {
    background-color: #101010;
    color: #e0e0e0;
    border-radius: 8px;
}
#workspaces button.active {
    background-color: @accent;
}
"""


class ThemeImport(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.base = Path(self._tmp.name)
        theme_dir = self.base / "mytest"
        theme_dir.mkdir()
        (theme_dir / "style.css").write_text(SAMPLE_CSS)
        self._patches = [
            mock.patch.object(theme_import, "BAR_THEMES_DIR", self.base),
            mock.patch.object(theme_import, "load_pywal_colors", return_value=None),
        ]
        for p in self._patches:
            p.start()

    def tearDown(self) -> None:
        for p in self._patches:
            p.stop()
        self._tmp.cleanup()

    def test_list_themes(self) -> None:
        self.assertEqual(theme_import.list_themes(), ["mytest"])

    def test_parse_palette(self) -> None:
        palette = theme_import.parse_palette("mytest")
        self.assertIsNotNone(palette)
        self.assertEqual(palette["background"], "#101010")
        self.assertEqual(palette["accent"].lower(), "#ff00ff")

    def test_missing_theme_is_none(self) -> None:
        self.assertIsNone(theme_import.parse_palette("nope"))

    def test_traversal_name_is_none(self) -> None:
        self.assertIsNone(theme_import.parse_palette("../etc"))

    def test_import_then_remove(self) -> None:
        src = self.base / "src-theme"
        src.mkdir()
        (src / "style.css").write_text(SAMPLE_CSS)
        name = theme_import.import_theme(src)
        self.assertEqual(name, "src-theme")
        self.assertIn("src-theme", theme_import.list_themes())
        self.assertTrue(theme_import.remove_theme("src-theme"))
        self.assertNotIn("src-theme", theme_import.list_themes())


class Hexify(unittest.TestCase):
    def test_rgba_to_hex(self) -> None:
        self.assertEqual(themes.hexify("rgba(180, 180, 190, 1.00)"), "#b4b4be")

    def test_rgb_to_hex(self) -> None:
        self.assertEqual(themes.hexify("rgb(16, 16, 16)"), "#101010")

    def test_hex_passthrough(self) -> None:
        self.assertEqual(themes.hexify("#abcdef"), "#abcdef")

    def test_entry_shape(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            d = base / "t1"
            d.mkdir()
            (d / "style.css").write_text(SAMPLE_CSS)
            with mock.patch.object(theme_import, "BAR_THEMES_DIR", base), \
                 mock.patch.object(theme_import, "load_pywal_colors", return_value=None):
                entry = themes._theme_entry("t1")
            self.assertEqual(entry["name"], "t1")
            self.assertEqual(entry["palette"]["background"], "#101010")
            self.assertTrue(entry["palette"]["accent"].startswith("#"))


if __name__ == "__main__":
    unittest.main()
