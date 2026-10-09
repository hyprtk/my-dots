"""Unit tests for the start-menu file-browser backend (no Qt)."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import files  # noqa: E402


class ListDir(unittest.TestCase):
    def test_dirs_first_and_hidden_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            (base / "zeta").write_text("x")
            (base / "alpha").write_text("y")
            (base / "sub").mkdir()
            (base / ".hidden").write_text("z")
            result = files.list_dir(tmp)
            names = [e["name"] for e in result["entries"]]
            self.assertEqual(names[0], "sub")          # dir first
            self.assertNotIn(".hidden", names)
            self.assertEqual(names[1:], ["alpha", "zeta"])
            self.assertTrue(result["entries"][0]["is_dir"])
            self.assertEqual(result["entries"][1]["size"], 1)

    def test_missing_dir_is_empty(self) -> None:
        result = files.list_dir("/no/such/dir/xyz")
        self.assertEqual(result["entries"], [])


class XdgPlaces(unittest.TestCase):
    def test_reads_user_dirs_in_order(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "Desktop").mkdir()
            (home / "Downloads").mkdir()
            conf = home / ".config"
            conf.mkdir()
            (conf / "user-dirs.dirs").write_text(
                'XDG_DESKTOP_DIR="$HOME/Desktop"\n'
                'XDG_DOWNLOAD_DIR="$HOME/Downloads"\n'
                'XDG_MUSIC_DIR="$HOME/NotHere"\n'
            )
            with mock.patch.dict(os.environ, {"HOME": str(home)}):
                places = files.xdg_places()
            self.assertEqual([p["label"] for p in places], ["Desktop", "Downloads"])

    def test_fallback_to_conventional_names(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / "Documents").mkdir()
            with mock.patch.dict(os.environ, {"HOME": str(home)}):
                places = files.xdg_places()
            self.assertEqual(places, [{"label": "Documents", "path": str(home / "Documents")}])


if __name__ == "__main__":
    unittest.main()
