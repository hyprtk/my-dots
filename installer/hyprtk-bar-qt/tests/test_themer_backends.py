"""Unit tests for the themer backends (pywal / icons / lock), toolkit-free."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import icons, lock, pywal  # noqa: E402


class PywalParse(unittest.TestCase):
    def test_from_sh_parses_16_colors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            p = Path(tmp) / "colors.sh"
            lines = ["background='#111111'", "foreground='#eeeeee'"]
            for i in range(16):
                lines.append(f"color{i}='#{i:02x}{i:02x}{i:02x}'")
            p.write_text("\n".join(lines))
            old = pywal.COLORS_SH
            pywal.COLORS_SH = p
            try:
                out = pywal._from_sh()
            finally:
                pywal.COLORS_SH = old
            self.assertEqual(out["color0"], "#000000")
            self.assertEqual(out["color15"], "#0f0f0f")
            self.assertEqual(out["background"], "#111111")

    def test_norm_accepts_bare_hex(self) -> None:
        self.assertEqual(pywal._norm("2AACCC"), "#2aaccc")
        self.assertEqual(pywal._norm("#2AACCC44"), "#2aaccc")
        self.assertEqual(pywal._norm("nope"), "")


class IconsPresets(unittest.TestCase):
    def test_presets_are_25(self) -> None:
        self.assertEqual(len(icons.presets()), 25)
        names = [p["name"] for p in icons.presets()]
        self.assertIn("blue", names)
        self.assertIn("violet", names)

    def test_apply_hex_validates(self) -> None:
        # Invalid hex must not run papirus-folders (returns False early).
        self.assertFalse(icons.apply_hex("nonsense"))

    def test_current_detects_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            (base / "folder-blue.svg").write_text("x")
            (base / "folder.svg").symlink_to(base / "folder-blue.svg")
            old = icons.ICON_THEME_DIR
            icons.ICON_THEME_DIR = base
            try:
                self.assertEqual(icons.current(), "blue")
            finally:
                icons.ICON_THEME_DIR = old


class LockSettings(unittest.TestCase):
    def test_read_and_set_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "config"
            cfg.write_text('font="Cantarell"\nring-color=2AACCC\ninside-color=090B15\n')
            old_sway, old_hypr = lock.SWAYLOCK, lock.HYPRLOCK_CONF
            lock.SWAYLOCK, lock.HYPRLOCK_CONF = cfg, Path(tmp) / "nope.conf"
            try:
                data = lock.read()
                self.assertEqual(data["kind"], "swaylock")
                colors = {i["key"]: i for i in data["items"] if i["color"]}
                self.assertIn("ring-color", colors)
                self.assertTrue(lock.set_value("ring-color", "FF0000"))
                self.assertIn("ring-color=FF0000", cfg.read_text())
            finally:
                lock.SWAYLOCK, lock.HYPRLOCK_CONF = old_sway, old_hypr

    def test_set_unknown_key_appends(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "config"
            cfg.write_text("ring-color=2AACCC\n")
            old_sway, old_hypr = lock.SWAYLOCK, lock.HYPRLOCK_CONF
            lock.SWAYLOCK, lock.HYPRLOCK_CONF = cfg, Path(tmp) / "nope.conf"
            try:
                self.assertTrue(lock.set_value("text-color", "FFFFFF"))
                self.assertIn("text-color=FFFFFF", cfg.read_text())
            finally:
                lock.SWAYLOCK, lock.HYPRLOCK_CONF = old_sway, old_hypr


class LockPywalSync(unittest.TestCase):
    def test_sync_swaylock_rewrites_only_colors(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            cfg = Path(tmp) / "config"
            cfg.write_text('font="Cantarell"\nsomeflag\nring-color=000000\n')
            old_sway = lock.SWAYLOCK
            lock.SWAYLOCK = cfg
            palette = ["%02x%02x%02x" % (i, i, i) for i in range(16)]
            try:
                with mock.patch.object(lock, "_wal_hex", return_value=palette):
                    self.assertTrue(lock.sync_swaylock())
            finally:
                lock.SWAYLOCK = old_sway
            text = cfg.read_text()
            self.assertIn('font="Cantarell"', text)        # non-color kept
            self.assertIn("someflag", text)                # bare flag kept
            self.assertIn("ring-color=060606", text)       # index 6, opaque
            self.assertIn("inside-color=00000044", text)   # index 0 + alpha

    def test_sync_swaylock_needs_palette(self) -> None:
        with mock.patch.object(lock, "_wal_hex", return_value=[]):
            self.assertFalse(lock.sync_swaylock())


if __name__ == "__main__":
    unittest.main()
