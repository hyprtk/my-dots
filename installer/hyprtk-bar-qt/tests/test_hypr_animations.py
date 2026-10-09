"""Unit tests for the Hyprland border-animation mirror (no compositor)."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import hypr_animations as ha  # noqa: E402


class BorderPeriod(unittest.TestCase):
    def test_custom_speed(self) -> None:
        cfg = {"theme": {"border_animation": True}, "animations": {"mode": "custom", "speed": 8}}
        self.assertEqual(ha.border_period_ms(cfg), 800)

    def test_custom_floor(self) -> None:
        cfg = {"theme": {"border_animation": True}, "animations": {"mode": "custom", "speed": 1}}
        self.assertEqual(ha.border_period_ms(cfg), 200)

    def test_custom_missing_speed(self) -> None:
        cfg = {"theme": {"border_animation": True}, "animations": {"mode": "custom"}}
        self.assertIsNone(ha.border_period_ms(cfg))

    def test_border_animation_off(self) -> None:
        cfg = {"theme": {"border_animation": False}, "animations": {"mode": "custom", "speed": 8}}
        self.assertIsNone(ha.border_period_ms(cfg))

    def test_file_mode_reads_animations_file(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "hyprland.lua").write_text('require("animations-low")\n')
            (root / "animations-low.lua").write_text(
                'hl.animation({ leaf = "borderangle", enabled = true, speed = 5 })\n'
            )
            with mock.patch.object(ha, "HYPR_DIRS", (root,)):
                cfg = {"theme": {"border_animation": True}, "animations": {"mode": "low"}}
                self.assertEqual(ha.border_period_ms(cfg), 500)

    def test_parse_animations(self) -> None:
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "animations-high.lua"
            p.write_text('hl.animation({ leaf = "border", enabled = false, speed = 3 })\n')
            anims = ha._parse_animations(p)
            self.assertEqual(anims["border"]["speed"], 3)
            self.assertFalse(anims["border"]["enabled"])


if __name__ == "__main__":
    unittest.main()
