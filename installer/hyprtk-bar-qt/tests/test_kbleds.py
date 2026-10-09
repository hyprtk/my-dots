"""Unit tests for the keyboard-LED backend (no Qt)."""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import kbleds  # noqa: E402


class KbLeds(unittest.TestCase):
    def test_led_on_is_bool(self) -> None:
        self.assertIsInstance(kbleds.led_on("capslock"), bool)

    def test_sample_shape(self) -> None:
        s = kbleds.sample()
        self.assertEqual(set(s), {"caps", "num"})
        self.assertIsInstance(s["caps"], bool)
        self.assertIsInstance(s["num"], bool)


if __name__ == "__main__":
    unittest.main()
