"""Unit tests for the toolkit-free sysmon backend (no Qt, no compositor)."""

from __future__ import annotations

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import sysmon  # noqa: E402


class CpuFraction(unittest.TestCase):
    def test_half_busy(self) -> None:
        # 10 idle of 100 total jiffies elapsed -> 0.9 busy
        self.assertAlmostEqual(sysmon.cpu_fraction((100, 200), (110, 300)), 0.9)

    def test_fully_idle(self) -> None:
        self.assertAlmostEqual(sysmon.cpu_fraction((0, 0), (100, 100)), 0.0)

    def test_no_elapsed_is_zero(self) -> None:
        self.assertEqual(sysmon.cpu_fraction((5, 5), (5, 5)), 0.0)


class ByteRates(unittest.TestCase):
    def test_rates(self) -> None:
        rx, tx = sysmon.byte_rates((0, 0), (1000, 500), 2.0)
        self.assertAlmostEqual(rx, 500.0)
        self.assertAlmostEqual(tx, 250.0)

    def test_zero_dt(self) -> None:
        self.assertEqual(sysmon.byte_rates((0, 0), (1000, 500), 0.0), (0.0, 0.0))

    def test_counter_reset_clamps(self) -> None:
        rx, tx = sysmon.byte_rates((1000, 1000), (0, 0), 1.0)
        self.assertEqual((rx, tx), (0.0, 0.0))


class MemFraction(unittest.TestCase):
    def test_in_range(self) -> None:
        f = sysmon.mem_fraction()
        self.assertGreaterEqual(f, 0.0)
        self.assertLessEqual(f, 1.0)


class DiskUsage(unittest.TestCase):
    def test_root_reports_totals(self) -> None:
        frac, used, total = sysmon.disk_usage("/")
        self.assertGreater(total, 0.0)
        self.assertGreaterEqual(frac, 0.0)
        self.assertLessEqual(frac, 1.0)
        self.assertGreaterEqual(used, 0.0)

    def test_bad_path_is_zero(self) -> None:
        self.assertEqual(sysmon.disk_usage("/no/such/path/here"), (0.0, 0.0, 0.0))


if __name__ == "__main__":
    unittest.main()
