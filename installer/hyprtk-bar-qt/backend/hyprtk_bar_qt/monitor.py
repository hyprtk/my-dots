"""Stream a full system-monitor sample as JSON lines (one object per line).

The Qt system-monitor dialog (``surface/SysMonitor.qml``) spawns this while it
is open and parses stdout, so the heavy /proc, /sys, lsblk, nvidia-smi and
hyprctl work stays in Python and out of QML — mirroring the GTK4 bar's
``monitor.py`` data path.

Run standalone (``python3 monitor.py``), as a module
(``python -m hyprtk_bar_qt.monitor``), or via the QML ``MonitorData`` singleton.
Each line carries only the pages requested with ``--pages``::

    {"cpu": {...}, "memory": {...}, "disk": {...}, "drives": [...],
     "net": {...}, "gpu": {...}, "gpu_static": {...}}
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import threading
import time
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from hyprtk_bar_qt import monitor_data
else:
    from . import monitor_data

ALL_PAGES = ("cpu", "memory", "disks", "network", "gpu", "apps")


class MonitorSampler:
    """Collects one richer sample per enabled page.

    Rate samplers (CPU / disk / net) keep the previous counter read between
    calls, so consecutive :meth:`sample` calls yield real usage deltas. Static
    GPU identity is fetched once, off the sampling path, and cached.
    """

    def __init__(self, pages=ALL_PAGES, disk_path="/", iface="auto", active="cpu"):
        self.pages = [p for p in pages if p in ALL_PAGES]
        self.active = active
        self._cpu = monitor_data.CpuSampler() if "cpu" in self.pages else None
        self._disk = (
            monitor_data.DiskSampler((disk_path,)) if "disks" in self.pages else None
        )
        self._net = (
            monitor_data.NetSampler(iface) if "network" in self.pages else None
        )
        self._gpu = monitor_data.GpuSampler() if "gpu" in self.pages else None
        self._static = monitor_data.gpu_static(use_cache=True)
        self._static_lock = threading.Lock()
        if "gpu" in self.pages and self._static is None:
            threading.Thread(target=self._fetch_static, daemon=True).start()

    def _fetch_static(self) -> None:
        try:
            info = monitor_data.gpu_static(use_cache=False)
        except Exception:
            info = None
        if info:
            with self._static_lock:
                self._static = info

    def sample(self) -> dict:
        out: dict = {}
        if self._cpu is not None:
            out["cpu"] = self._cpu.sample()
        if "memory" in self.pages:
            out["memory"] = monitor_data.memory()
        if self._disk is not None:
            out["disk"] = self._disk.sample()
            out["drives"] = monitor_data.drives()
        if self._net is not None:
            out["net"] = self._net.sample()
        if self._gpu is not None:
            out["gpu"] = self._gpu.sample()
            with self._static_lock:
                out["gpu_static"] = self._static
        # The process walk is the most expensive sampler, so only run it while
        # the Apps page is actually on screen (matches the GTK bar).
        if "apps" in self.pages and self.active == "apps":
            out["apps"] = monitor_data.top_processes()
            out["uid"] = os.getuid()
        return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(
        description="stream system-monitor samples as JSON lines"
    )
    ap.add_argument("--interval", type=float, default=1.0, help="seconds between samples")
    ap.add_argument(
        "--pages", default=",".join(ALL_PAGES), help="comma list of pages to sample"
    )
    ap.add_argument("--disk-path", default="/", help="mount point for disk usage")
    ap.add_argument("--iface", default="auto", help="network interface or 'auto'")
    ap.add_argument(
        "--active", default="cpu", help="the page currently on screen (gates 'apps')"
    )
    args = ap.parse_args(argv)

    pages = tuple(p.strip() for p in args.pages.split(",") if p.strip())
    sampler = MonitorSampler(
        pages, disk_path=args.disk_path, iface=args.iface, active=args.active
    )

    try:
        while True:
            print(json.dumps(sampler.sample()), flush=True)
            time.sleep(max(0.1, args.interval))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
