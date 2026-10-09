"""Stream system samples as JSON lines (one object per line).

Standalone on purpose: run as ``python3 sysmon.py`` or ``python -m
hyprtk_bar_qt.sysmon``. The QML ``SysMonitor``/``Net`` modules spawn it and parse
stdout, so the heavy /proc parsing stays in Python and out of QML.

Emits e.g. ``{"cpu": 0.12, "mem": 0.41, "rx": 1024.0, "tx": 512.0}`` every
``--interval`` seconds, where rx/tx are bytes per second.
"""

from __future__ import annotations

import argparse
import json
import os
import time


def _cpu_times() -> tuple[int, int]:
    """Return (idle_jiffies, total_jiffies) from /proc/stat."""
    with open("/proc/stat") as f:
        parts = f.readline().split()
    vals = [int(x) for x in parts[1:]]
    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
    return idle, sum(vals)


def cpu_fraction(prev: tuple[int, int], cur: tuple[int, int]) -> float:
    """Fraction (0..1) of CPU time that was busy between two samples."""
    d_idle = cur[0] - prev[0]
    d_total = cur[1] - prev[1]
    if d_total <= 0:
        return 0.0
    return max(0.0, min(1.0, 1.0 - d_idle / d_total))


def mem_fraction() -> float:
    """Fraction (0..1) of RAM in use (used = total - available)."""
    info: dict[str, int] = {}
    with open("/proc/meminfo") as f:
        for line in f:
            key, _, rest = line.partition(":")
            try:
                info[key.strip()] = int(rest.strip().split()[0])
            except (ValueError, IndexError):
                continue
    total = info.get("MemTotal", 0)
    avail = info.get("MemAvailable", info.get("MemFree", 0))
    if total <= 0:
        return 0.0
    return max(0.0, min(1.0, (total - avail) / total))


def _net_bytes() -> tuple[int, int]:
    """Total (rx, tx) bytes across non-loopback interfaces from /proc/net/dev."""
    rx = tx = 0
    with open("/proc/net/dev") as f:
        for line in f:
            if ":" not in line:
                continue
            iface, _, rest = line.partition(":")
            if iface.strip() == "lo":
                continue
            fields = rest.split()
            if len(fields) < 9:
                continue
            try:
                rx += int(fields[0])
                tx += int(fields[8])
            except ValueError:
                continue
    return rx, tx


def byte_rates(prev: tuple[int, int], cur: tuple[int, int], dt: float) -> tuple[float, float]:
    """(rx, tx) bytes per second between two counter reads over ``dt`` seconds."""
    if dt <= 0:
        return 0.0, 0.0
    return (max(0.0, (cur[0] - prev[0]) / dt),
            max(0.0, (cur[1] - prev[1]) / dt))


def disk_usage(path: str = "/") -> tuple[float, float, float]:
    """(used_fraction, used_gb, total_gb) for the filesystem at ``path``."""
    try:
        st = os.statvfs(path)
    except OSError:
        return 0.0, 0.0, 0.0
    total = st.f_blocks * st.f_frsize
    free = st.f_bavail * st.f_frsize
    if total <= 0:
        return 0.0, 0.0, 0.0
    used = total - free
    gib = 1024.0 ** 3
    return max(0.0, min(1.0, used / total)), used / gib, total / gib


def sample(state: dict | None, disk_path: str = "/") -> tuple[dict, dict]:
    """Take one sample; return (new_state, output_dict).

    ``state`` is the previous sample's state (or None on the first call).
    """
    now = time.monotonic()
    cpu = _cpu_times()
    net = _net_bytes()
    disk_pct, disk_used, disk_total = disk_usage(disk_path)

    out = {
        "cpu": 0.0, "mem": round(mem_fraction(), 4), "rx": 0.0, "tx": 0.0,
        "disk": round(disk_pct, 4), "disk_used": round(disk_used, 2),
        "disk_total": round(disk_total, 2),
    }
    if state is not None:
        out["cpu"] = round(cpu_fraction(state["cpu"], cpu), 4)
        rx, tx = byte_rates(state["net"], net, now - state["t"])
        out["rx"] = round(rx, 1)
        out["tx"] = round(tx, 1)

    return {"cpu": cpu, "net": net, "t": now}, out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="stream /proc system samples as JSON lines")
    ap.add_argument("--interval", type=float, default=1.0, help="seconds between samples")
    ap.add_argument("--disk-path", default="/", help="filesystem to report usage for")
    args = ap.parse_args(argv)

    state: dict | None = None
    try:
        while True:
            state, data = sample(state, args.disk_path)
            print(json.dumps(data), flush=True)
            time.sleep(max(0.1, args.interval))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
