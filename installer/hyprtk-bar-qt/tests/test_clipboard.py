"""Unit tests for the toolkit-free clipboard backend (no Qt, no cliphist)."""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import clipboard  # noqa: E402


class ParseList(unittest.TestCase):
    def test_text_entry(self) -> None:
        entries = clipboard.parse_list("12\thello world")
        self.assertEqual(entries, [{"id": "12", "image": None, "info": "hello world"}])

    def test_image_entry(self) -> None:
        line = "7\t[[ binary data 79 KiB png 611x704 ]]"
        entries = clipboard.parse_list(line)
        self.assertEqual(len(entries), 1)
        self.assertEqual(entries[0]["id"], "7")
        self.assertEqual(entries[0]["image"], "png")
        self.assertIn("611x704", entries[0]["info"])

    def test_skips_malformed(self) -> None:
        text = "no-tab line\nabc\tnot-a-number\nyy\ttab but nonnumeric id"
        self.assertEqual(clipboard.parse_list(text), [])

    def test_preview_is_truncated(self) -> None:
        entries = clipboard.parse_list("1\t" + "x" * 1000)
        self.assertLessEqual(len(entries[0]["info"]), clipboard._MAX_PREVIEW)


if __name__ == "__main__":
    unittest.main()
