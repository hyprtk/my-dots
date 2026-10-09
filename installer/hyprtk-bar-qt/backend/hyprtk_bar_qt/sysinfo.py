"""One-shot system-information snapshot for the SysInfo desktop widget.

Toolkit-free; the widget runs this on its refresh timer and renders the rows.
Prints one JSON object.
"""

from __future__ import annotations

import json
import platform
import socket
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from hyprtk_bar_qt import monitor_data
else:
    from . import monitor_data


def os_name() -> str:
    try:
        with open("/etc/os-release") as handle:
            for line in handle:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return platform.system() or "Linux"


def cpu_model() -> str:
    try:
        with open("/proc/cpuinfo") as handle:
            for line in handle:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return ""


def uptime() -> str:
    try:
        with open("/proc/uptime") as handle:
            return monitor_data.fmt_uptime(float(handle.read().split()[0]))
    except (OSError, ValueError, IndexError):
        return "--"


def gpu_model(use_cache: bool = True) -> str:
    try:
        info = monitor_data.gpu_static(use_cache=use_cache)
    except Exception:
        info = None
    if not info:
        return ""
    return " ".join(p for p in (info.get("manufacturer"), info.get("model")) if p).strip()


def gather() -> dict:
    mem = monitor_data.memory()
    disk_list = monitor_data.drives()
    disk_total = sum(float(d.get("size_b") or 0) for d in disk_list)
    return {
        "host": socket.gethostname(),
        "os": os_name(),
        "kernel": platform.release(),
        "uptime": uptime(),
        "cpu": cpu_model(),
        "gpu": gpu_model(),
        "mem_total": mem.get("total_gb", 0.0),
        "disk_count": len(disk_list),
        "disk_total": monitor_data.fmt_bytes(disk_total),
    }


def main(argv: list[str] | None = None) -> int:
    print(json.dumps(gather()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
