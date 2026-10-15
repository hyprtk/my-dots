"""Unit tests for the tray-hover info backend (no Qt)."""

from __future__ import annotations

import os
import sys
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "backend"))

from hyprtk_bar_qt import trayinfo  # noqa: E402


class NmcliConnections(unittest.TestCase):
    def test_parses_active_connections(self) -> None:
        text = "Wired connection 1:802-3-ethernet:enp7s0\nlo:loopback:lo\n"
        conns = trayinfo.parse_connections(text)
        self.assertEqual(conns[0], {"name": "Wired connection 1",
                                    "type": "802-3-ethernet", "device": "enp7s0"})
        self.assertEqual(len(conns), 2)

    def test_escaped_colon_kept(self) -> None:
        conns = trayinfo.parse_connections("Home\\: Guest:802-11-wireless:wlp2s0")
        self.assertEqual(conns[0]["name"], "Home: Guest")


class NmcliDevice(unittest.TestCase):
    def test_indexed_and_bare_keys(self) -> None:
        text = (
            "IP4.ADDRESS[1]:192.168.0.10/24\n"
            "IP4.GATEWAY:192.168.0.1\n"
            "GENERAL.STATE:100 (connected)\n"
        )
        d = trayinfo.parse_device(text)
        self.assertEqual(d["IP4.ADDRESS[1]"], "192.168.0.10/24")
        self.assertEqual(d["IP4.ADDRESS"], "192.168.0.10/24")
        self.assertEqual(d["IP4.GATEWAY"], "192.168.0.1")


class ConnType(unittest.TestCase):
    def test_kinds(self) -> None:
        self.assertEqual(trayinfo._conn_type_key("802-11-wireless"), "wifi")
        self.assertEqual(trayinfo._conn_type_key("802-3-ethernet"), "eth")
        self.assertEqual(trayinfo._conn_type_key("bridge"), "other")


class Bluetooth(unittest.TestCase):
    def test_parse_show(self) -> None:
        text = (
            "Controller BC:54:2F:B8:21:4D (public)\n"
            "\tName: dozer-hyprtk\n"
            "\tAlias: dozer-hyprtk\n"
            "\tPowered: no\n"
        )
        info = trayinfo.parse_bt_show(text)
        self.assertFalse(info["powered"])
        self.assertEqual(info["alias"], "dozer-hyprtk")
        self.assertEqual(info["mac"], "BC:54:2F:B8:21:4D")

    def test_parse_devices(self) -> None:
        text = "Device A0:5A:5D:00:11:22 WH-1000XM4\nDevice 00:11:22:33:44:55\n"
        devices = trayinfo.parse_bt_devices(text)
        self.assertEqual(devices[0], {"name": "WH-1000XM4", "mac": "A0:5A:5D:00:11:22"})
        self.assertEqual(devices[1]["name"], "00:11:22:33:44:55")


class Sampler(unittest.TestCase):
    def test_network_block(self) -> None:
        def fake_run(cmd, timeout=3.0):
            if "connection" in cmd:
                return "Wired connection 1:802-3-ethernet:enp7s0\n"
            if "device" in cmd:
                return (
                    "IP4.ADDRESS[1]:192.168.0.10/24\n"
                    "IP4.GATEWAY:192.168.0.1\n"
                    "GENERAL.STATE:100 (connected)\n"
                )
            return ""

        net = {"all": [{"name": "enp7s0", "down_bps": 12.0, "up_bps": 3.0, "ip": ""}]}
        with mock.patch.object(trayinfo, "_run", side_effect=fake_run), \
                mock.patch.object(trayinfo.monitor_data, "NetSampler") as ns:
            ns.return_value.sample.return_value = net
            out = trayinfo.TrayInfoSampler().sample()
        n = out["network"]
        self.assertTrue(n["available"])
        self.assertEqual(n["device"], "enp7s0")
        self.assertEqual(n["ip4"], "192.168.0.10/24")
        self.assertEqual(n["down_bps"], 12.0)
        self.assertEqual(n["up_bps"], 3.0)

    def test_unavailable_when_no_nmcli(self) -> None:
        with mock.patch.object(trayinfo, "_run", return_value=""), \
                mock.patch.object(trayinfo.monitor_data, "NetSampler") as ns:
            ns.return_value.sample.return_value = {"all": []}
            out = trayinfo.TrayInfoSampler().sample()
        self.assertFalse(out["network"]["available"])


if __name__ == "__main__":
    unittest.main()
