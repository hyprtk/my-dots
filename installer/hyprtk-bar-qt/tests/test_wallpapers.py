"""Unit tests for the toolkit-free wallpaper scanner (no Qt, no wallpapers)."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
import unittest.mock
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import wallpapers  # noqa: E402


class Scan(unittest.TestCase):
    def test_filters_images_and_sorts(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            for name in ("b.png", "a.jpg", "notes.txt", "c.webp"):
                (base / name).write_bytes(b"x")
            (base / "sub").mkdir()
            (base / "sub" / "nested.png").write_bytes(b"x")
            result = wallpapers.scan(tmp)
            names = [Path(p).name for p in result]
            self.assertEqual(names, ["a.jpg", "b.png", "c.webp"])

    def test_missing_dir_is_empty(self) -> None:
        self.assertEqual(wallpapers.scan("/no/such/dir/here"), [])

    def test_apply_missing_file_fails(self) -> None:
        self.assertFalse(wallpapers.apply("/no/such/image.png"))


class RandomApply(unittest.TestCase):
    def test_random_image_picks_from_dir(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            for name in ("a.png", "b.jpg"):
                (Path(tmp) / name).write_bytes(b"x")
            chosen = wallpapers.random_image(tmp)
            self.assertIn(Path(chosen).name, {"a.png", "b.jpg"})

    def test_random_image_empty_dir_is_none(self) -> None:
        self.assertIsNone(wallpapers.random_image("/no/such/dir/here"))

    def test_random_apply_uses_apply(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "a.png").write_bytes(b"x")
            with unittest.mock.patch.object(wallpapers, "apply", return_value=True) as apply:
                chosen = wallpapers.random_apply(tmp)
                self.assertEqual(Path(chosen).name, "a.png")
                apply.assert_called_once()

    def test_random_apply_empty_dir_is_none(self) -> None:
        self.assertIsNone(wallpapers.random_apply("/no/such/dir/here"))


class Thumbs(unittest.TestCase):
    def test_thumb_path_deterministic(self) -> None:
        self.assertEqual(wallpapers.thumb_path("/tmp/x.png"),
                         wallpapers.thumb_path("/tmp/x.png"))
        self.assertTrue(str(wallpapers.thumb_path("/tmp/x.png")).endswith(".jpg"))

    def test_ensure_thumb_and_scan_items(self) -> None:
        try:
            from PIL import Image
        except ImportError:  # pragma: no cover
            self.skipTest("PIL and no thumbnailer available")
        with tempfile.TemporaryDirectory() as tmp:
            Image.new("RGB", (8, 8), (200, 100, 50)).save(str(Path(tmp) / "a.png"))
            with unittest.mock.patch.object(wallpapers, "THUMB_DIR", Path(tmp) / "thumbs"):
                items = wallpapers.scan_items(tmp)
                self.assertEqual(len(items), 1)
                self.assertIn("path", items[0])
                self.assertEqual(items[0]["path"], str((Path(tmp) / "a.png").resolve()))
                thumb = items[0]["thumb"]
                if thumb is not None:  # only if a thumbnailer exists
                    self.assertTrue(Path(thumb).is_file())
    def test_scan_items_no_thumbs(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            (Path(tmp) / "a.png").write_bytes(b"x")
            items = wallpapers.scan_items(tmp, with_thumbs=False)
            self.assertEqual(items[0]["thumb"], None)


if __name__ == "__main__":
    unittest.main()
