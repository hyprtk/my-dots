"""Stream tray-hover info as JSON lines (one object per line).

The tray module (``bar/modules/Tray.qml``) spawns this through the ``TrayInfo``
singleton while the tray is enabled, then renders the current sample in the
hover tooltip. It answers the two tray apps whose glyph alone is not enough:

* **network** (nm-applet) — active connection, device, IPv4/gateway/DNS and
  per-interface up/down rates.
* **bluetooth** (blueman) — adapter state and the connected devices.

Everything is defensive: any missing tool or parse failure degrades to an
``available: false`` block rather than raising, so the tooltip can always fall
back to the item title. Rates reuse the tested ``monitor_data.NetSampler``
(/proc/net/dev deltas); connection detail comes from ``nmcli``.

Emits e.g.::

    {"network": {...}, "bluetooth": {...}}
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from hyprtk_bar_qt import monitor_data
else:
    from . import monitor_data

# Active connection types worth surfacing (nmcli's TYPE field).
_WIFI_HINTS = ("wireless", "wifi", "wi-fi")
_ETH_HINTS = ("ethernet", "802-3")


def _run(cmd: list[str], timeout: float = 3.0) -> str:
    """Run a command, returning stdout ("" on any failure)."""
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return out.stdout if out.returncode == 0 else ""


# ── nmcli parsing ─────────────────────────────────────────────────

def _split_nmcli(line: str) -> list[str]:
    """Split an nmcli -t line on unescaped ':' separators.

    nmcli escapes literal colons in values as ``\\:`` (e.g. in an IPv6 address),
    so a naive ``split(":")`` would corrupt them.
    """
    fields: list[str] = []
    cur: list[str] = []
    escaped = False
    for ch in line:
        if escaped:
            cur.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == ":":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    fields.append("".join(cur))
    return fields


def parse_connections(text: str) -> list[dict]:
    """Parse ``nmcli -t -f NAME,TYPE,DEVICE connection show --active``.

    Returns ``[{name, type, device}]`` (order preserved).
    """
    out: list[dict] = []
    for line in text.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = _split_nmcli(line)
        if len(parts) < 3:
            continue
        out.append({"name": parts[0], "type": parts[1], "device": parts[2]})
    return out


def parse_device(text: str) -> dict:
    """Parse ``nmcli -t ... device show`` into ``{KEY: value}``.

    Multi-valued rows keep their ``KEY[i]`` spelling (``IP4.ADDRESS[1]``); the
    bare ``KEY`` is kept for the first occurrence too, so callers can try
    ``IP4.ADDRESS[1]`` then ``IP4.ADDRESS``.
    """
    out: dict[str, str] = {}
    for line in text.splitlines():
        if ":" not in line:
            continue
        key, _, value = line.partition(":")
        key = key.strip()
        value = value.strip()
        if not key:
            continue
        out.setdefault(key, value)
        bare = key.split("[", 1)[0]
        out.setdefault(bare, value)
    return out


def _conn_type_key(nm_type: str) -> str:
    t = nm_type.lower()
    if any(h in t for h in _WIFI_HINTS):
        return "wifi"
    if any(h in t for h in _ETH_HINTS):
        return "eth"
    return "other"


# ── bluetoothctl parsing ──────────────────────────────────────────

def parse_bt_show(text: str) -> dict:
    """Parse ``bluetoothctl show`` into ``{powered, alias, name, mac}``."""
    powered = False
    alias = name = mac = ""
    for raw in text.splitlines():
        line = raw.strip()
        low = line.lower()
        if low.startswith("powered:"):
            powered = line.split(":", 1)[1].strip().lower().startswith("yes")
        elif low.startswith("alias:"):
            alias = line.split(":", 1)[1].strip()
        elif low.startswith("name:"):
            name = line.split(":", 1)[1].strip()
        elif low.startswith("controller ") and not mac:
            parts = line.split()
            if len(parts) > 1:
                mac = parts[1]
    return {"powered": powered, "alias": alias, "name": name, "mac": mac}


def parse_bt_devices(text: str) -> list[dict]:
    """Parse ``bluetoothctl devices Connected`` into ``[{name, mac}]``."""
    out: list[dict] = []
    for raw in text.splitlines():
        line = raw.strip()
        if not line.startswith("Device "):
            continue
        parts = line.split(" ", 2)
        if len(parts) < 2:
            continue
        mac = parts[1]
        name = parts[2].strip() if len(parts) > 2 and parts[2].strip() else mac
        out.append({"name": name, "mac": mac})
    return out


class TrayInfoSampler:
    """One tray-tooltip sample per call (network + bluetooth).

    Keeps a ``NetSampler`` between calls so the network rates are real deltas.
    """

    def __init__(self, iface: str = "auto"):
        self._net = monitor_data.NetSampler(iface)

    def _active_connection(self) -> dict | None:
        text = _run(
            ["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"]
        )
        conns = parse_connections(text)
        for conn in conns:
            if conn["device"] and _conn_type_key(conn["type"]) != "other":
                return conn
        # Fall back to the first active connection with a device at all.
        for conn in conns:
            if conn["device"]:
                return conn
        return None

    def _network(self, net: dict) -> dict:
        conn = self._active_connection()
        if conn is None:
            return {"available": False}
        device = conn["device"]
        type_key = _conn_type_key(conn["type"])
        detail = parse_device(
            _run(
                ["nmcli", "-t", "-f",
                 "IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,GENERAL.STATE",
                 "device", "show", device]
            )
        )
        rates = next(
            (i for i in net.get("all", []) if i.get("name") == device), {}
        )
        ip4 = (
            detail.get("IP4.ADDRESS[1]")
            or detail.get("IP4.ADDRESS")
            or rates.get("ip", "")
        )
        return {
            "available": True,
            "connection": conn["name"],
            "device": device,
            "type": type_key,
            "state": detail.get("GENERAL.STATE", ""),
            "ip4": ip4,
            "ip6": detail.get("IP6.ADDRESS[1]") or detail.get("IP6.ADDRESS", ""),
            "gateway": detail.get("IP4.GATEWAY", ""),
            "dns": detail.get("IP4.DNS[1]") or detail.get("IP4.DNS", ""),
            "ssid": conn["name"] if type_key == "wifi" else "",
            "down_bps": round(rates.get("down_bps", 0.0), 1),
            "up_bps": round(rates.get("up_bps", 0.0), 1),
        }

    @staticmethod
    def _bluetooth() -> dict:
        show = _run(["bluetoothctl", "show"], timeout=4.0)
        info = parse_bt_show(show)
        devices = parse_bt_devices(
            _run(["bluetoothctl", "devices", "Connected"], timeout=4.0)
        )
        return {
            "available": bool(show) or bool(devices),
            "powered": info["powered"],
            "adapter": info["alias"] or info["name"] or "",
            "mac": info["mac"],
            "devices": devices,
        }

    def sample(self) -> dict:
        net = self._net.sample()
        return {"network": self._network(net), "bluetooth": self._bluetooth()}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="stream tray-hover info as JSON lines")
    ap.add_argument("--interval", type=float, default=2.0, help="seconds between samples")
    ap.add_argument("--iface", default="auto", help="network interface or 'auto'")
    args = ap.parse_args(argv)

    sampler = TrayInfoSampler(args.iface)
    try:
        while True:
            print(json.dumps(sampler.sample()), flush=True)
            time.sleep(max(0.2, args.interval))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
