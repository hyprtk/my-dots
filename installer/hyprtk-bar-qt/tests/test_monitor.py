"""Unit tests for the toolkit-free system-monitor backend (no Qt)."""

from __future__ import annotations

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import dimm, monitor, monitor_data, proc_action  # noqa: E402


class Formatters(unittest.TestCase):
    def test_fmt_bytes(self) -> None:
        self.assertEqual(monitor_data.fmt_bytes(0), "0 B")
        self.assertEqual(monitor_data.fmt_bytes(512), "512 B")
        self.assertEqual(monitor_data.fmt_bytes(1024), "1.0 KiB")
        self.assertEqual(monitor_data.fmt_bytes(1536), "1.5 KiB")
        self.assertEqual(monitor_data.fmt_bytes(1024 ** 3), "1.0 GiB")

    def test_fmt_bytes_clamps_negative(self) -> None:
        self.assertEqual(monitor_data.fmt_bytes(-5), "0 B")

    def test_fmt_rate(self) -> None:
        self.assertEqual(monitor_data.fmt_rate(2048), "2.0 KiB/s")

    def test_fmt_uptime(self) -> None:
        self.assertEqual(monitor_data.fmt_uptime(90), "1m")
        self.assertEqual(monitor_data.fmt_uptime(3600 + 300), "1h 5m")
        self.assertEqual(monitor_data.fmt_uptime(86400 + 7200), "1d 2h 0m")
        self.assertEqual(monitor_data.fmt_uptime("bogus"), "--")


class Memory(unittest.TestCase):
    def test_shape(self) -> None:
        m = monitor_data.memory()
        for key in (
            "used_pct", "used_gb", "total_gb", "avail_gb",
            "buffers_gb", "cached_gb", "swap_pct", "swap_used_gb", "swap_total_gb",
        ):
            self.assertIn(key, m)


class Dmidecode(unittest.TestCase):
    def test_parse_populated_and_empty(self) -> None:
        text = (
            "Memory Device\n"
            "\tSize: 16384 MB\n"
            "\tLocator: DIMM_A1\n"
            "\tBank Locator: BANK 0\n"
            "Memory Device\n"
            "\tSize: No Module Installed\n"
            "\tLocator: DIMM_A2\n"
            "\tBank Locator: BANK 0\n"
        )
        slots = monitor_data.parse_dmidecode(text)
        self.assertEqual(len(slots), 2)
        self.assertTrue(slots[0]["populated"])
        self.assertAlmostEqual(slots[0]["size_gb"], 16.0)
        self.assertFalse(slots[1]["populated"])
        self.assertIsNone(slots[1]["size_gb"])


class MonitorSampler(unittest.TestCase):
    def test_pages_filter_memory_only(self) -> None:
        s = monitor.MonitorSampler(pages=("memory",))
        out = s.sample()
        self.assertEqual(set(out), {"memory"})

    def test_pages_filter_cpu_memory(self) -> None:
        s = monitor.MonitorSampler(pages=("cpu", "memory"))
        out = s.sample()
        self.assertEqual(set(out), {"cpu", "memory"})
        self.assertIn("cores", out["cpu"])
        self.assertGreaterEqual(len(out["cpu"]["cores"]), 1)

    def test_unknown_pages_dropped(self) -> None:
        s = monitor.MonitorSampler(pages=("memory", "bogus"))
        self.assertEqual(s.pages, ["memory"])

    def test_apps_gated_by_active_page(self) -> None:
        s = monitor.MonitorSampler(pages=("apps",), active="cpu")
        self.assertEqual(s.sample(), {})

    def test_apps_sampled_when_active(self) -> None:
        s = monitor.MonitorSampler(pages=("apps",), active="apps")
        out = s.sample()
        self.assertIn("apps", out)
        self.assertIn("uid", out)
        self.assertIsInstance(out["apps"], list)


class DimmCli(unittest.TestCase):
    def test_ok_when_slots_present(self) -> None:
        slots = [{"locator": "DIMM_A1", "populated": True, "size_gb": 16.0}]
        with mock.patch.object(monitor_data, "dimm_slots", return_value=slots):
            self.assertEqual(dimm.main([]), 0)

    def test_fails_when_unavailable(self) -> None:
        with mock.patch.object(monitor_data, "dimm_slots", return_value=None):
            self.assertEqual(dimm.main([]), 1)


class ProcAction(unittest.TestCase):
    def test_kill_missing_pid_fails(self) -> None:
        self.assertEqual(proc_action.main(["kill", "21474833"]), 1)

    def test_launch_missing_pid_fails(self) -> None:
        self.assertEqual(proc_action.main(["launch", "21474833"]), 1)


if __name__ == "__main__":
    unittest.main()
