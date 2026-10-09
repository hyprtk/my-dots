"""Unit tests for the desktop-widget backends (weather, sysinfo). No network."""

from __future__ import annotations

import json
import os
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import sysinfo, visualizer, weather, widgets_layout  # noqa: E402


class WeatherDescribe(unittest.TestCase):
    def test_known_code(self) -> None:
        label, day, night = weather.describe(0)
        self.assertEqual(label, "Clear")
        self.assertNotEqual(day, night)

    def test_unknown_code(self) -> None:
        self.assertEqual(weather.describe(12345)[0], "Unknown")

    def test_bad_code(self) -> None:
        self.assertEqual(weather.describe("nope")[0], "Unknown")


class WeatherCache(unittest.TestCase):
    def test_roundtrip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "weather.json"
            with mock.patch.object(weather, "CACHE_PATH", path):
                self.assertIsNone(weather.load_cache())
                weather.save_cache({"city": "London", "fetched": 1.0})
                self.assertEqual(weather.load_cache()["city"], "London")

    def test_fresh_cache_skips_fetch(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "weather.json"
            with mock.patch.object(weather, "CACHE_PATH", path), \
                 mock.patch.object(weather, "fetch_weather") as fetch:
                weather.save_cache({"city": "London", "fetched": time.time()})
                result = weather.get_weather("London", max_age=900)
                fetch.assert_not_called()
                self.assertEqual(result["city"], "London")

    def test_stale_cache_fetches(self) -> None:
        fresh = {"city": "Paris", "fetched": time.time()}
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "weather.json"
            with mock.patch.object(weather, "CACHE_PATH", path), \
                 mock.patch.object(weather, "fetch_weather", return_value=fresh) as fetch:
                weather.save_cache({"city": "Paris", "fetched": time.time() - 9999})
                result = weather.get_weather("Paris", max_age=900)
                fetch.assert_called_once()
                self.assertEqual(result["city"], "Paris")


class Visualizer(unittest.TestCase):
    def test_parse_frame(self) -> None:
        self.assertEqual(visualizer.parse_frame("0;50;100"), [0.0, 0.5, 1.0])

    def test_parse_frame_clamps_and_rejects(self) -> None:
        self.assertEqual(visualizer.parse_frame("150;-10"), [1.0, 0.0])
        self.assertEqual(visualizer.parse_frame("oops;12"), [])

    def test_synthetic_frame_shape(self) -> None:
        frame = visualizer.synthetic_frame(1.0, 16)
        self.assertEqual(len(frame), 16)
        self.assertTrue(all(0.0 <= v <= 1.0 for v in frame))

    def test_resolve_binary_rejects_missing(self) -> None:
        self.assertIsNone(visualizer.resolve_binary("definitely-not-a-real-binary-xyz"))


class SnapLayout(unittest.TestCase):
    def test_no_groups_is_empty(self) -> None:
        self.assertEqual(widgets_layout.layout({"clock": {"width": 220}}), {})

    def test_horizontal_group(self) -> None:
        cfg = {
            "clock": {"snap_group": "g", "snap_axis": "horizontal", "snap_order": 1,
                       "width": 220, "margin_x": 100, "margin_y": 50, "position": "free"},
            "disk": {"snap_group": "g", "snap_axis": "horizontal", "snap_order": 2,
                      "width": 300, "margin_x": 0, "margin_y": 0, "position": "free"},
        }
        out = widgets_layout.layout(cfg)
        self.assertEqual(out["clock"]["x"], 100)
        self.assertEqual(out["clock"]["y"], 50)
        # uniform cell = widest (300); second sits one cell + spacing right
        self.assertEqual(out["disk"]["x"], 100 + 300 + widgets_layout.SPACING)
        self.assertEqual(out["disk"]["w"], 300)

    def test_vertical_group(self) -> None:
        cfg = {
            "a": {"snap_group": "g", "snap_axis": "vertical", "snap_order": 1,
                   "width": 200, "height": 100, "margin_x": 10, "margin_y": 10, "position": "free"},
            "b": {"snap_group": "g", "snap_axis": "vertical", "snap_order": 2,
                   "width": 200, "height": 120, "position": "free"},
        }
        out = widgets_layout.layout(cfg)
        self.assertEqual(out["a"]["y"], 10)
        self.assertEqual(out["b"]["y"], 10 + 120 + widgets_layout.SPACING)

    def test_measured_heights_avoid_overlap(self) -> None:
        # Auto-height widgets (config height 0) must not stack on top of each
        # other: the measured heights supply the cell height.
        cfg = {
            "a": {"snap_group": "g", "snap_axis": "vertical", "snap_order": 1,
                   "width": 200, "height": 0, "margin_x": 10, "margin_y": 10, "position": "free"},
            "b": {"snap_group": "g", "snap_axis": "vertical", "snap_order": 2,
                   "width": 200, "height": 0, "position": "free"},
        }
        out = widgets_layout.layout(cfg, heights={"a": {"w": 200, "h": 150}, "b": {"w": 200, "h": 90}})
        self.assertEqual(out["a"]["h"], 150)
        self.assertEqual(out["b"]["y"], 10 + 150 + widgets_layout.SNAP_GAP)

    def test_per_member_scale_fills_cell(self) -> None:
        # The cell is the largest natural member; smaller members scale up
        # (clamped to SNAP_SCALE_MAX), larger members scale down — as GTK.
        cfg = {
            "small": {"snap_group": "g", "snap_axis": "horizontal", "snap_order": 1,
                       "width": 100, "height": 100, "margin_x": 0, "margin_y": 0, "position": "free"},
            "big": {"snap_group": "g", "snap_axis": "horizontal", "snap_order": 2,
                     "width": 300, "height": 200, "position": "free"},
        }
        out = widgets_layout.layout(cfg)
        self.assertEqual(out["small"]["w"], 300)
        self.assertEqual(out["small"]["h"], 200)
        # small: min(300/100, 200/100)=2.0 -> clamped 2.0 * 0.97
        self.assertAlmostEqual(out["small"]["scale"], 2.0 * widgets_layout.SNAP_FIT_MARGIN, places=3)
        # big: min(300/300, 200/200)=1.0 * 0.97
        self.assertAlmostEqual(out["big"]["scale"], 1.0 * widgets_layout.SNAP_FIT_MARGIN, places=3)

    def test_group_clamped_to_bounds_origin_keeps_members_aligned(self) -> None:
        # The whole group is clamped to the usable origin (bar inset), so the top
        # member is not shifted alone (which overlapped it with the next).
        cfg = {
            "a": {"snap_group": "g", "snap_axis": "vertical", "snap_order": 0,
                   "margin_x": 100, "margin_y": 8, "position": "free", "width": 200, "height": 100},
            "b": {"snap_group": "g", "snap_axis": "vertical", "snap_order": 1,
                   "margin_x": 100, "margin_y": 118, "position": "free", "width": 200, "height": 100},
        }
        out = widgets_layout.layout(cfg, bounds={"x0": 0, "y0": 38, "w": 1000, "h": 900})
        self.assertEqual(out["a"]["y"], 38)
        self.assertEqual(out["b"]["y"], 38 + 100 + widgets_layout.SNAP_GAP)

    def test_anchor_stays_on_first_member(self) -> None:
        # Snapping a widget onto an existing group must NOT relocate the group:
        # it stays anchored on its top/left-most member, and the joining widget
        # is placed in the next cell.
        cfg = {
            "clock": {"snap_group": "g1", "snap_axis": "horizontal", "snap_order": 0,
                       "width": 100, "height": 100, "margin_x": 0, "margin_y": 0, "position": "free"},
            "disk": {"position": "free", "margin_x": 320, "margin_y": 4,
                      "snap_group": "g1", "snap_axis": "horizontal", "snap_order": 1,
                      "width": 100, "height": 100},
        }
        out = widgets_layout.layout(cfg)
        self.assertEqual(out["clock"]["x"], 0)                     # group did not move
        self.assertEqual(out["disk"]["x"], 100 + widgets_layout.SNAP_GAP)



class SnapDrop(unittest.TestCase):
    def test_snap_axis(self) -> None:
        a = {"x": 0, "y": 0, "w": 100, "h": 100}
        right = {"x": 108, "y": 5, "w": 100, "h": 100}   # 8px gap, vertical overlap
        far = {"x": 400, "y": 400, "w": 100, "h": 100}
        below = {"x": 5, "y": 108, "w": 100, "h": 100}
        self.assertEqual(widgets_layout.snap_axis(a, right)[1], "horizontal")
        self.assertEqual(widgets_layout.snap_axis(a, below)[1], "vertical")
        self.assertIsNone(widgets_layout.snap_axis(a, far)[1])

    def test_snap_joins_nearest_and_orders(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"widgets": {
                "clock": {"position": "free", "margin_x": 0, "margin_y": 0},
                "disk": {"position": "free", "margin_x": 500, "margin_y": 500},
            }}))
            rects = {
                "clock": {"x": 0, "y": 0, "w": 100, "h": 100},
                "disk": {"x": 500, "y": 500, "w": 100, "h": 100},
            }
            # Drop disk just to the right of clock.
            res = widgets_layout.snap("disk", 110, 4, rects, path)
            self.assertTrue(res["snapped"])
            self.assertEqual(res["axis"], "horizontal")
            data = json.loads(path.read_text())["widgets"]
            self.assertEqual(data["clock"]["snap_group"], data["disk"]["snap_group"])
            self.assertNotEqual(data["clock"]["snap_group"], "")
            self.assertEqual(data["clock"]["snap_order"], 0)  # left-most anchors
            self.assertEqual(data["disk"]["snap_order"], 1)

    def test_snap_none_detaches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"widgets": {
                "clock": {"position": "free", "margin_x": 0, "margin_y": 0, "snap_group": "g1"},
            }}))
            rects = {"clock": {"x": 1000, "y": 700, "w": 100, "h": 100}}
            res = widgets_layout.snap("clock", 1000, 700, rects, path)
            self.assertFalse(res["snapped"])
            self.assertEqual(json.loads(path.read_text())["widgets"]["clock"]["snap_group"], "")

    def test_snap_joins_group_by_bounding_box(self) -> None:
        # A widget dropped beside/under a *group* joins it even though it is not
        # edge-adjacent to any single member, and the group keeps its axis.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"widgets": {
                "a": {"position": "free", "snap_group": "g1", "snap_axis": "vertical",
                       "snap_order": 0, "margin_x": 3000, "margin_y": 100},
                "b": {"position": "free", "snap_group": "g1", "snap_axis": "vertical",
                       "snap_order": 1, "margin_x": 3000, "margin_y": 300},
                "c": {"position": "free", "margin_x": 0, "margin_y": 0},
            }}))
            rects = {
                "a": {"x": 3000, "y": 100, "w": 300, "h": 150},
                "b": {"x": 3000, "y": 260, "w": 300, "h": 150},
                "c": {"x": 3030, "y": 440, "w": 300, "h": 120},
            }
            res = widgets_layout.snap("c", 3030, 440, rects, path)
            self.assertTrue(res["snapped"])
            self.assertEqual(res["group"], "g1")
            self.assertEqual(res["axis"], "vertical")
            data = json.loads(path.read_text())["widgets"]
            self.assertEqual(data["c"]["snap_group"], "g1")
            self.assertEqual(data["c"]["snap_order"], 2)   # appended after a, b

    def test_repositioning_member_translates_group(self) -> None:
        # Dragging an existing member to a new spot moves the group so that
        # member stays where it was dropped (the anchor shifts).
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"widgets": {
                "a": {"position": "free", "snap_group": "g1", "snap_axis": "vertical",
                       "snap_order": 0, "margin_x": 100, "margin_y": 100},
                "b": {"position": "free", "snap_group": "g1", "snap_axis": "vertical",
                       "snap_order": 1, "margin_x": 100, "margin_y": 260},
            }}))
            rects = {
                "a": {"x": 100, "y": 100, "w": 200, "h": 150},
                "b": {"x": 100, "y": 260, "w": 200, "h": 150},
            }
            res = widgets_layout.snap("b", 100, 280, rects, path)
            self.assertTrue(res["snapped"])
            data = json.loads(path.read_text())["widgets"]
            self.assertEqual(data["a"]["margin_y"], 120)   # 280 - 1*(150+10)
            self.assertEqual(data["b"]["snap_order"], 1)

    def test_resnap_own_group_keeps_order(self) -> None:
        # Re-dropping a member onto its own group keeps its slot (no reorder).
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"widgets": {
                "a": {"position": "free", "snap_group": "g1", "snap_axis": "horizontal",
                       "snap_order": 0, "margin_x": 0, "margin_y": 0},
                "b": {"position": "free", "snap_group": "g1", "snap_axis": "horizontal",
                       "snap_order": 1, "margin_x": 110, "margin_y": 0},
            }}))
            rects = {
                "a": {"x": 0, "y": 0, "w": 100, "h": 100},
                "b": {"x": 110, "y": 0, "w": 100, "h": 100},
            }
            res = widgets_layout.snap("b", 110, 0, rects, path)
            self.assertTrue(res["snapped"])
            data = json.loads(path.read_text())["widgets"]
            self.assertEqual(data["b"]["snap_order"], 1)


class SaveLayout(unittest.TestCase):
    def test_writes_margins_keeps_membership(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"widgets": {
                "a": {"snap_group": "g", "snap_order": 0, "margin_x": 0, "margin_y": 0},
            }}))
            ok = widgets_layout.save_layout({"a": {"x": 38, "y": 241, "w": 100, "h": 100}}, path)
            self.assertTrue(ok)
            b = json.loads(path.read_text())["widgets"]["a"]
            self.assertEqual((b["margin_x"], b["margin_y"]), (38, 241))
            self.assertEqual(b["snap_group"], "g")

    def test_missing_config_fails(self) -> None:
        self.assertFalse(widgets_layout.save_layout({"a": {"x": 1, "y": 2}}, Path("/no/such/config.json")))


class SetOpacity(unittest.TestCase):
    def test_sets_all_widgets(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text(json.dumps({"widgets": {"a": {"opacity": 0.75}, "b": {}}}))
            self.assertTrue(widgets_layout.set_opacity(0.8, path))
            w = json.loads(path.read_text())["widgets"]
            self.assertEqual(w["a"]["opacity"], 0.8)
            self.assertEqual(w["b"]["opacity"], 0.8)

    def test_missing_config_fails(self) -> None:
        self.assertFalse(widgets_layout.set_opacity(0.5, Path("/no/such/config.json")))


class SetPosition(unittest.TestCase):
    def test_writes_free_position_and_detaches(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "config.json"
            path.write_text('{"widgets": {"clock": {"position": "top-right", "snap_group": "g3"}}}')
            self.assertTrue(widgets_layout.set_position("clock", 500, 300, path))
            import json
            data = json.loads(path.read_text())
            self.assertEqual(data["widgets"]["clock"]["position"], "free")
            self.assertEqual(data["widgets"]["clock"]["margin_x"], 500)
            self.assertEqual(data["widgets"]["clock"]["margin_y"], 300)
            self.assertEqual(data["widgets"]["clock"]["snap_group"], "")  # detached

    def test_missing_config_fails(self) -> None:
        self.assertFalse(widgets_layout.set_position("clock", 1, 2, Path("/no/such/config.json")))


class SysInfo(unittest.TestCase):
    def test_gather_shape(self) -> None:
        with mock.patch.object(sysinfo.monitor_data, "gpu_static", return_value=None):
            info = sysinfo.gather()
        for key in ("host", "os", "kernel", "uptime", "cpu", "mem_total", "disk_count", "disk_total"):
            self.assertIn(key, info)


if __name__ == "__main__":
    unittest.main()
