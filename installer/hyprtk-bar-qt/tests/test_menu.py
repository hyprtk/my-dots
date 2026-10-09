"""Unit tests for the start-menu favourites/recents backend (no Qt)."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import menu  # noqa: E402


class Recents(unittest.TestCase):
    def test_prepend_and_cap(self) -> None:
        self.assertEqual(menu.record_recent(["b", "c"], "a", 2), ["a", "b"])

    def test_dedupe_moves_to_front(self) -> None:
        self.assertEqual(menu.record_recent(["a", "b"], "b"), ["b", "a"])

    def test_empty_id_is_noop(self) -> None:
        self.assertEqual(menu.record_recent(["a"], ""), ["a"])


class Favorites(unittest.TestCase):
    def test_add_remove(self) -> None:
        self.assertEqual(menu.toggle_favorite([], "x"), ["x"])
        self.assertEqual(menu.toggle_favorite(["x", "y"], "x"), ["y"])


class FileIO(unittest.TestCase):
    def test_record_and_favorite_persist(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            with mock.patch.object(menu, "BAR_CONFIG", path):
                menu.record_launch("firefox")
                menu.record_launch("kitty")
                menu.set_favorite("firefox", True)
                restored = menu.load_menu()
            self.assertEqual(restored["recents"], ["kitty", "firefox"])
            self.assertIn("firefox", restored["favorites"])

    def test_max_recents_respected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text('{"menu": {"max_recents": 2}}')
            with mock.patch.object(menu, "BAR_CONFIG", path):
                for app in ("a", "b", "c"):
                    menu.record_launch(app)
                self.assertEqual(menu.load_menu()["recents"], ["c", "b"])

    def test_clear_recents(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text('{"menu": {"recents": ["a", "b"]}}')
            with mock.patch.object(menu, "BAR_CONFIG", path):
                menu.clear_recents()
                self.assertEqual(menu.load_menu()["recents"], [])


if __name__ == "__main__":
    unittest.main()
