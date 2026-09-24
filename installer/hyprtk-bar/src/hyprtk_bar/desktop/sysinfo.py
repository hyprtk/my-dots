"""System-information desktop widget: host, OS, kernel, CPU, GPU, memory, disks."""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.sysinfo
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import os
import platform
import socket
import threading

import gi
gi.require_version("Gtk", "3.0")

from gi.repository import GLib, Gtk  # noqa: E402

from .sampled import SampledWidget, clear, label, row  # noqa: E402

log = logging.getLogger("hyprtk_bar.desktop.sysinfo")


def _os_name() -> str:
    try:
        with open("/etc/os-release") as handle:
            for line in handle:
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except OSError:
        pass
    return platform.system() or "Linux"


def _cpu_model() -> str:
    try:
        with open("/proc/cpuinfo") as handle:
            for line in handle:
                if line.startswith("model name"):
                    return line.split(":", 1)[1].strip()
    except OSError:
        pass
    return ""


def _uptime() -> str:
    from ..monitor_data import fmt_uptime

    try:
        with open("/proc/uptime") as handle:
            return fmt_uptime(float(handle.read().split()[0]))
    except (OSError, ValueError, IndexError):
        return "--"


class SysInfoWidget(SampledWidget):
    WIDGET_ID = "sysinfo"
    DEFAULT_REFRESH_S = 10

    def __init__(self, cfg: dict, block: dict):
        self._rows_box: Gtk.Box | None = None
        self._gpu: str | None = None
        self._gpu_fetching = False
        super().__init__(cfg, block)

    def build_content(self) -> None:
        self._rows_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self.root.pack_start(self._rows_box, False, False, 0)

    def collect(self) -> dict:
        from ..monitor_data import drives, fmt_bytes, memory

        mem = memory()
        disk_list = drives()
        disk_total = sum(float(d.get("size_b") or 0) for d in disk_list)
        if self._gpu is None and not self._gpu_fetching:
            self._start_gpu_fetch()
        return {
            "host": socket.gethostname(),
            "os": _os_name(),
            "kernel": platform.release(),
            "uptime": _uptime(),
            "cpu": _cpu_model(),
            "gpu": self._gpu,
            "mem_total": mem.get("total_gb", 0.0),
            "disks": (len(disk_list), fmt_bytes(disk_total)),
        }

    def _start_gpu_fetch(self) -> None:
        self._gpu_fetching = True

        def work() -> None:
            from ..monitor_data import gpu_static

            try:
                info = gpu_static(use_cache=False) or gpu_static(use_cache=True)
            except Exception:
                info = None
            model = ""
            if info:
                model = " ".join(
                    part for part in (info.get("manufacturer"), info.get("model")) if part
                ).strip()
            GLib.idle_add(self._on_gpu, model or "—")

        threading.Thread(target=work, daemon=True).start()

    def _on_gpu(self, model: str) -> bool:
        self._gpu = model
        self._gpu_fetching = False
        return GLib.SOURCE_REMOVE

    def render(self, data: dict) -> None:
        if self._rows_box is None:
            return
        clear(self._rows_box)
        rows = [
            ("show_host", "\uf109", "Host", data.get("host")),
            ("show_os", "\uf17c", "OS", data.get("os")),
            ("show_kernel", "\uf17c", "Kernel", data.get("kernel")),
            ("show_uptime", "\uf017", "Uptime", data.get("uptime")),
            ("show_cpu", "\uf2db", "CPU", data.get("cpu")),
            ("show_gpu", "\uf108", "GPU", data.get("gpu")),
            ("show_memory", "\uf1c0", "Memory", f"{data.get('mem_total', 0.0):.1f} GiB"),
        ]
        for flag, glyph, key, value in rows:
            if not self._block.get(flag, True) or not value:
                continue
            self._rows_box.pack_start(self._info_row(glyph, key, str(value)), False, False, 0)
        if self._block.get("show_disks", True) and data.get("disks"):
            count, size = data["disks"]
            self._rows_box.pack_start(
                self._info_row("\uf0a0", "Disks", f"{count} × {size}"), False, False, 0
            )
        self._rows_box.show_all()

    def on_content_scale(self, scale: float) -> None:
        self._sample()

    def _info_row(self, glyph: str, key: str, value: str) -> Gtk.Box:
        from ..widgets import Glyph

        line = row(8)
        icon = Glyph(glyph, "widget-icon")
        icon.set_pixel_size(max(8, int(round(16 * self._content_scale))))
        line.pack_start(icon, False, False, 0)
        name = label(key, "info-key")
        name.set_size_request(72, -1)
        line.pack_start(name, False, False, 0)
        val = label(value, "info-val")
        val.set_ellipsize(3)
        line.pack_start(val, True, True, 0)
        return line
