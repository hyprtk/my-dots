"""Pure (no-GTK) data readers for the system monitor dialog.

Everything is plain Python over /proc + /sys so the readers work without a
display and are trivially testable. Every reader is defensive: on any error it
returns a zero/empty value rather than raising. Rate readers (CPU, disk I/O,
network) are sampler classes that keep a previous sample and compute deltas.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · monitor_data
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import time
from pathlib import Path

_KB = 1024
_GB = 1024 ** 3

HWMON = Path("/sys/class/hwmon")
DRM = Path("/sys/class/drm")
DIMM_CACHE = Path.home() / ".cache" / "hyprtk-bar" / "dimm.json"
DIMM_TTL = 24 * 3600
GPU_CACHE = Path.home() / ".cache" / "hyprtk-bar" / "gpu.json"
GPU_TTL = 24 * 3600

_GPU_VENDORS = {"1002": "AMD", "10de": "NVIDIA", "8086": "Intel"}


def _cache_fresh(path: Path, ttl: float) -> bool:
    try:
        return time.time() - path.stat().st_mtime < ttl
    except OSError:
        return False

_PHYS_DEVICE = re.compile(r"^(sd[a-z]+|nvme\d+n\d+|vd[a-z]+|mmcblk\d+)$")


def _read_text(path) -> str:
    try:
        return Path(path).read_text().strip()
    except (OSError, ValueError):
        return ""


# ── formatting ────────────────────────────────────────────────────

def fmt_bytes(n: float) -> str:
    """Human-readable size (B/KiB/MiB/GiB/TiB)."""
    try:
        n = float(n)
    except (TypeError, ValueError):
        n = 0.0
    n = max(n, 0.0)
    units = ["B", "KiB", "MiB", "GiB", "TiB"]
    i = 0
    while n >= 1024 and i < len(units) - 1:
        n /= 1024
        i += 1
    if i == 0:
        return f"{int(n)} B"
    return f"{n:.1f} {units[i]}"


# ── process control ───────────────────────────────────────────────

def kill_process(pid: int, force: bool = False) -> bool:
    """Send SIGTERM (or SIGKILL when ``force``) to a pid.

    User-owned processes are killed directly; system (root/other) processes go
    through the scoped ``hyprtk-system-kill`` sudo helper so the bar can act
    on them without a password and without blanket NOPASSWD. Returns False on
    failure (permission, missing pid, helper absent).
    """
    signal_name = "-KILL" if force else "-TERM"
    uid = _read_pid_uid(pid)
    if uid is None:
        return False
    try:
        if uid == os.getuid():
            # Own process: no elevation needed.
            return subprocess.run(
                ["kill", signal_name, str(pid)], capture_output=True, timeout=5
            ).returncode == 0
        # System process: use the scoped sudo helper.
        helper = "/usr/local/bin/hyprtk-system-kill"
        return subprocess.run(
            ["sudo", "-n", helper, str(pid), signal_name],
            capture_output=True, timeout=10,
        ).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def launch_process(pid: int) -> bool:
    """Launch a new instance of a process from its stored argv (detached).

    Re-runs the selected process's command line so "Launch" restarts the same
    app/process. Returns False when the process has no usable argv.
    """
    argv = _read_pid_cmdline(pid)
    if not argv:
        return False
    try:
        subprocess.Popen(argv, start_new_session=True)
        return True
    except (OSError, ValueError, subprocess.SubprocessError):
        return False


def fmt_rate(bps: float) -> str:
    return fmt_bytes(bps) + "/s"


def fmt_uptime(seconds: float) -> str:
    try:
        seconds = int(float(seconds))
    except (TypeError, ValueError):
        return "--"
    days, rem = divmod(seconds, 86400)
    hours, rem = divmod(rem, 3600)
    mins = rem // 60
    if days:
        return f"{days}d {hours}h {mins}m"
    if hours:
        return f"{hours}h {mins}m"
    return f"{mins}m"


# ── CPU ───────────────────────────────────────────────────────────

def _read_cpu_times() -> dict[str, tuple[int, int]]:
    """``/proc/stat`` -> {name: (total_jiffies, idle_jiffies)} for cpu/cpuN."""
    times: dict[str, tuple[int, int]] = {}
    try:
        with open("/proc/stat") as f:
            for line in f:
                parts = line.split()
                if not parts or not parts[0].startswith("cpu"):
                    continue
                vals = [int(v) for v in parts[1:]]
                idle = vals[3] + vals[4]
                times[parts[0]] = (sum(vals), idle)
    except (OSError, ValueError, IndexError):
        pass
    return times


def _loadavg() -> tuple[float, float, float]:
    try:
        fields = Path("/proc/loadavg").read_text().split()
        return (float(fields[0]), float(fields[1]), float(fields[2]))
    except (OSError, ValueError, IndexError):
        return (0.0, 0.0, 0.0)


def _uptime_s() -> float:
    try:
        return float(Path("/proc/uptime").read_text().split()[0])
    except (OSError, ValueError, IndexError):
        return 0.0


def _cpu_freq() -> tuple[int, int]:
    """(current_mhz, max_mhz) from the cpu0 cpufreq sysfs nodes."""
    cur = _read_text("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")
    mx = _read_text("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq")
    try:
        return int(cur) // 1000, int(mx) // 1000
    except ValueError:
        return 0, 0


def _process_count() -> int:
    try:
        return sum(1 for d in os.listdir("/proc") if d.isdigit())
    except OSError:
        return 0


def _thread_count() -> int:
    count = 0
    try:
        for d in os.listdir("/proc"):
            if not d.isdigit():
                continue
            status = Path("/proc", d, "status")
            try:
                for line in status.read_text().splitlines():
                    if line.startswith("Threads:"):
                        count += int(line.split()[1])
                        break
            except (OSError, ValueError, IndexError):
                continue
    except OSError:
        pass
    return count


def hwmon_temps() -> dict[str, float]:
    """All hwmon temps as {label: celsius}."""
    temps: dict[str, float] = {}
    try:
        for hw in HWMON.iterdir():
            name = _read_text(hw / "name")
            if not name:
                continue
            for entry in hw.iterdir():
                if not (entry.name.startswith("temp") and entry.name.endswith("_input")):
                    continue
                try:
                    value = int(entry.read_text().strip()) / 1000.0
                except (OSError, ValueError):
                    continue
                label = name
                lbl = _read_text(entry.with_name(entry.name[:-6] + "_label"))
                if lbl:
                    label = f"{name} {lbl}"
                temps[label] = value
    except OSError:
        pass
    return temps


class CpuSampler:
    """Overall + per-core CPU usage with a process/thread/uptime readout."""

    def __init__(self):
        self._prev: dict[str, tuple[int, int]] = {}
        self._model = self._cpu_model()

    @staticmethod
    def _cpu_model() -> str:
        try:
            with open("/proc/cpuinfo") as f:
                for line in f:
                    if line.startswith("model name"):
                        return line.split(":", 1)[1].strip()
        except OSError:
            pass
        return ""

    def sample(self, full: bool = True) -> dict:
        """CPU stats.

        ``full=False`` skips the two ``/proc``-scanning counts (processes /
        threads) that a CPU-only desktop widget never displays — those scans
        dominate the sampler's cost at a 1 Hz refresh.
        """
        cur = _read_cpu_times()
        prev = self._prev or cur
        self._prev = cur

        def pct(name: str) -> float:
            a, b = cur.get(name), prev.get(name)
            if not a or not b:
                return 0.0
            total = a[0] - b[0]
            if total <= 0:
                return 0.0
            return 100.0 * (total - (a[1] - b[1])) / total

        overall = pct("cpu")
        core_names = sorted(
            (k for k in cur if k.startswith("cpu") and k[3:].isdigit()),
            key=lambda s: int(s[3:]),
        )
        cores = [pct(k) for k in core_names]

        load = _loadavg()
        freq_cur, freq_max = _cpu_freq()
        uptime = _uptime_s()
        processes = _process_count() if full else None
        threads = _thread_count() if full else None
        temp_c = None
        temps = hwmon_temps()
        for label, value in temps.items():
            low = label.lower()
            if "k10temp" in low or "tctl" in low or "cpu" in low:
                temp_c = value
                break
        return {
            "overall": overall,
            "cores": cores,
            "load": load,
            "processes": processes,
            "threads": threads,
            "uptime_s": uptime,
            "freq_mhz": freq_cur,
            "freq_max_mhz": freq_max,
            "temp_c": temp_c,
            "temps": temps,
            "model": self._model,
        }


# ── memory ────────────────────────────────────────────────────────

def memory() -> dict:
    """RAM + swap usage from /proc/meminfo (values in GB / percent)."""
    data: dict[str, int] = {}
    try:
        with open("/proc/meminfo") as f:
            for line in f:
                key, _, rest = line.partition(":")
                data[key] = int(rest.split()[0])
    except (OSError, ValueError, IndexError):
        pass
    total = data.get("MemTotal", 0)
    if total <= 0:
        return {
            "used_pct": 0.0, "used_gb": 0.0, "total_gb": 0.0, "avail_gb": 0.0,
            "buffers_gb": 0.0, "cached_gb": 0.0,
            "swap_pct": 0.0, "swap_used_gb": 0.0, "swap_total_gb": 0.0,
        }
    avail = data.get("MemAvailable", total - data.get("MemFree", 0))
    used = total - avail
    swap_total = data.get("SwapTotal", 0)
    swap_used = swap_total - data.get("SwapFree", swap_total)
    return {
        "used_pct": 100.0 * used / total,
        "used_gb": used * _KB / _GB,
        "total_gb": total * _KB / _GB,
        "avail_gb": avail * _KB / _GB,
        "buffers_gb": data.get("Buffers", 0) * _KB / _GB,
        "cached_gb": data.get("Cached", 0) * _KB / _GB,
        "swap_pct": 100.0 * swap_used / swap_total if swap_total else 0.0,
        "swap_used_gb": swap_used * _KB / _GB,
        "swap_total_gb": swap_total * _KB / _GB,
    }


# ── disk ──────────────────────────────────────────────────────────

def _diskstats() -> dict[str, tuple[int, int]]:
    """``/proc/diskstats`` -> {device: (read_bytes, write_bytes)}."""
    out: dict[str, tuple[int, int]] = {}
    try:
        with open("/proc/diskstats") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 10:
                    continue
                name = parts[2]
                if not _PHYS_DEVICE.match(name):
                    continue
                try:
                    rbytes = int(parts[5]) * 512
                    wbytes = int(parts[9]) * 512
                except ValueError:
                    continue
                out[name] = (rbytes, wbytes)
    except OSError:
        pass
    return out


class DiskSampler:
    """Disk usage of a mount + aggregate read/write transfer rates."""

    def __init__(self, paths=("/",)):
        self._paths = paths
        self._prev: dict[str, tuple[int, int]] = {}

    def sample(self) -> dict:
        cur = _diskstats()
        prev = self._prev or cur
        self._prev = cur
        read_bps = write_bps = 0.0
        devices = []
        for name, (r0, w0) in cur.items():
            p = prev.get(name)
            rd = (r0 - p[0]) if p else 0
            wr = (w0 - p[1]) if p else 0
            devices.append(
                {"name": name, "read_bps": max(rd, 0), "write_bps": max(wr, 0)}
            )
            read_bps += max(rd, 0)
            write_bps += max(wr, 0)

        used_pct = used_gb = total_gb = 0.0
        try:
            usage = shutil.disk_usage(self._paths[0])
            used_pct = 100.0 * usage.used / usage.total
            used_gb = usage.used / _GB
            total_gb = usage.total / _GB
        except (OSError, IndexError):
            pass
        return {
            "used_pct": used_pct,
            "used_gb": used_gb,
            "total_gb": total_gb,
            "read_bps": read_bps,
            "write_bps": write_bps,
            "devices": devices,
        }


# ── network ───────────────────────────────────────────────────────

def _netdev() -> dict[str, tuple[int, int]]:
    """``/proc/net/dev`` -> {iface: (rx_bytes, tx_bytes)}."""
    out: dict[str, tuple[int, int]] = {}
    try:
        with open("/proc/net/dev") as f:
            next(f, None)
            next(f, None)
            for line in f:
                if ":" not in line:
                    continue
                name, rest = line.split(":", 1)
                fields = rest.split()
                if len(fields) < 9:
                    continue
                try:
                    rx, tx = int(fields[0]), int(fields[8])
                except ValueError:
                    continue
                out[name.strip()] = (rx, tx)
    except (OSError, StopIteration):
        pass
    return out


# IPs are re-read per interface per poll (1s); cache them briefly — addresses
# change only on (re)connect, never second-to-second.
_IP_TTL = 30.0
_IP_CACHE: dict[str, tuple[str, float]] = {}


def _iface_ip(iface: str) -> str:
    now = time.monotonic()
    cached = _IP_CACHE.get(iface)
    if cached is not None and now - cached[1] < _IP_TTL:
        return cached[0]
    try:
        out = subprocess.run(
            ["ip", "-4", "-o", "addr", "show", iface],
            capture_output=True, text=True, timeout=3,
        ).stdout
        m = re.search(r"inet\s+(\S+)", out)
        ip = m.group(1).split("/")[0] if m else ""
    except (OSError, subprocess.SubprocessError):
        ip = ""
    _IP_CACHE[iface] = (ip, now)
    return ip


def iface_kind(name: str) -> tuple[str, str, str]:
    """(type_key, label, Nerd Font glyph) for a network interface."""
    if Path("/sys/class/net", name, "wireless").exists():
        return "wifi", "Wi-Fi", "\uf1eb"          # fa-wifi
    try:
        devtype = int(_read_text(f"/sys/class/net/{name}/type"))
    except (TypeError, ValueError):
        devtype = 0
    if name == "lo" or devtype == 772:           # ARPHRD_LOOPBACK
        return "lo", "Loopback", "\uf0ec"        # fa-exchange
    # Virtual devices (bridges like virbr0/docker0) have no device symlink.
    if not Path("/sys/class/net", name, "device").exists():
        return "virt", "Virtual", "\uf233"       # fa-server
    if devtype == 1:                             # ARPHRD_ETHER
        return "eth", "Ethernet", "\uef44"       # fa-ethernet
    return "virt", "Virtual", "\uf233"           # fa-server


class NetSampler:
    """Per-interface up/down rates, auto-selecting the active interface."""

    def __init__(self, iface: str = "auto"):
        self._iface = iface
        self._prev: dict[str, tuple[int, int]] = {}

    def _pick(self, rates: dict) -> str:
        if rates:
            best = max(rates, key=lambda n: rates[n][0] + rates[n][1])
            if best != "lo" and rates[best][0] + rates[best][1] > 0:
                return best
        for name in rates:
            if name == "lo":
                continue
            if _read_text(f"/sys/class/net/{name}/operstate") == "up":
                return name
        # No traffic and nothing "up": fall back to any non-loopback interface.
        for name in rates:
            if name != "lo":
                return name
        return next(iter(rates), "")

    def sample(self) -> dict:
        cur = _netdev()
        prev = self._prev or cur
        self._prev = cur
        rates: dict[str, tuple[int, int]] = {}
        for name, (r0, t0) in cur.items():
            p = prev.get(name)
            rates[name] = (max(r0 - p[0], 0), max(t0 - p[1], 0)) if p else (0, 0)

        iface = self._iface
        if iface == "auto" or iface not in rates:
            iface = self._pick(rates)
        down, up = rates.get(iface, (0, 0))

        all_ifaces = []
        for name, (d, u) in rates.items():
            if name == "lo":
                continue
            kind = iface_kind(name)
            all_ifaces.append(
                {
                    "name": name,
                    "type_key": kind[0],
                    "type": kind[1],
                    "glyph": kind[2],
                    "ip": _iface_ip(name),
                    "down_bps": d,
                    "up_bps": u,
                }
            )
        all_ifaces.sort(
            key=lambda i: (
                {"eth": 0, "wifi": 1, "virt": 2}.get(i["type_key"], 9),
                i["name"],
            )
        )

        kind = iface_kind(iface) if iface else ("", "", "\uf1eb")
        return {
            "iface": iface,
            "down_bps": down,
            "up_bps": up,
            "ip": _iface_ip(iface),
            "type": kind[1],
            "type_key": kind[0],
            "glyph": kind[2],
            "all": all_ifaces,
        }


# ── GPU (AMD / NVIDIA / Intel) ───────────────────────────────────

_GPU_DRIVERS = {
    "amdgpu": "AMD",
    "radeon": "AMD",
    "nvidia": "NVIDIA",
    "nouveau": "NVIDIA",
    "i915": "Intel",
    "xe": "Intel",
}

# Attributes only exist on the PCI device dir (cardN/device); try the common
# spellings across drivers (i915 per-GT layout vs xe tile layout) defensively.
_INTEL_FREQ_CUR = [
    "gt/gt0/rps_cur_freq_mhz",
    "gt_cur_freq_mhz",
    "tile0/gt0/freq0/cur_freq",
    "freq0/cur_freq",
]
_INTEL_FREQ_MAX = [
    "gt/gt0/rps_RP0_freq_mhz",
    "gt_RP0_freq_mhz",
    "tile0/gt0/freq0/rp0_freq",
    "tile0/gt0/freq0/max_freq",
    "freq0/rp0_freq",
    "freq0/max_freq",
]
_INTEL_IDLE = [
    "gt/gt0/rc6_residency_ms",
    "power/rc6_residency_ms",
    "tile0/gt0/gtidle/idle_residency_ms",
    "gtidle/idle_residency_ms",
]

_NVIDIA_QUERY = (
    "nvidia-smi",
    "--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,"
    "power.draw,fan.speed,clocks.sm,clocks.mem",
    "--format=csv,noheader,nounits",
)

# nvidia-smi cache (see GpuSampler._nvidia_sample).
_NVIDIA_CACHE: dict = {"value": None, "t": 0.0}


def _driver_of(dev: Path) -> str:
    """Kernel driver name bound to a GPU PCI device (amdgpu / nvidia / i915 / xe)."""
    try:
        target = (dev / "driver").resolve()
        return target.name
    except OSError:
        return ""


def _pci_is_discrete(dev: Path) -> bool:
    """Best-effort discrete-vs-integrated guess from the PCI bus address.

    Integrated GPUs sit on the root bus (``0000:00:xx.x``); add-in / dGPU
    devices are on a non-zero bus (``0000:01:00.0`` etc). Used only to prefer
    a discrete GPU when several are present.
    """
    try:
        addr = dev.resolve().name  # e.g. 0000:01:00.0
    except OSError:
        return False
    parts = addr.split(":")
    return len(parts) > 1 and parts[1] != "00"


def _iter_gpu_devices():
    """Yield (driver, pci_device_dir) for every real GPU card in /sys/class/drm.

    ``cardN/device`` is a symlink to the PCI device; each physical GPU has its
    own cardN. Drivers that expose no usable live metrics (nouveau) are still
    yielded so a system that only has them reports identity, not nothing.
    """
    seen = set()
    for card in DRM.iterdir():
        name = card.name
        if not name.startswith("card") or not name[4:].isdigit():
            continue
        dev = card / "device"
        driver = _driver_of(dev)
        if driver not in _GPU_DRIVERS:
            continue
        try:
            key = str(dev.resolve())
        except OSError:
            key = str(dev)
        if key in seen:
            continue
        seen.add(key)
        yield driver, dev


def _pick_gpu() -> tuple[str, Path] | None:
    """Auto-select the primary GPU (prefers a discrete/performance card).

    Returns ``(driver, pci_device_dir)`` or None. Ranking prefers, in order:
    NVIDIA discrete -> AMD discrete -> Intel discrete (Arc) -> AMD integrated
    -> Intel integrated. Within the same tier the first card wins.
    """
    tier = {"nvidia": 0, "amdgpu": 1, "nouveau": 2, "xe": 3, "i915": 3}
    best = None
    best_key = None
    for driver, dev in _iter_gpu_devices():
        t = tier.get(driver, 9)
        if t == 3:  # i915 / xe: prefer discrete Arc over the iGPU
            t = 2 if _pci_is_discrete(dev) else 4
        key = (t, 0 if _pci_is_discrete(dev) else 1)
        if best_key is None or key < best_key:
            best_key = key
            best = (driver, dev)
    return best


def _hwmon_for(dev: Path) -> Path | None:
    """The hwmon dir belonging to a specific GPU PCI device (by symlink)."""
    try:
        want = str(dev.resolve())
    except OSError:
        return None
    try:
        for hw in HWMON.iterdir():
            try:
                if str((hw / "device").resolve()) == want:
                    return hw
            except OSError:
                continue
    except OSError:
        pass
    return None


def _find_attr(dev: Path, rel_candidates: list[str]) -> Path | None:
    """First existing attribute under a device dir among candidate paths."""
    for rel in rel_candidates:
        p = dev / rel
        if p.is_file():
            return p
    return None


def _read_pp_dpm(dev: Path, attr: str) -> tuple[int | None, int | None]:
    """(current_mhz, max_mhz) from a ``pp_dpm_*`` clock list (the ``*`` is current)."""
    try:
        lines = (dev / attr).read_text().splitlines()
    except OSError:
        return None, None
    cur = mx = None
    for line in lines:
        m = re.match(r"\s*\d+:\s*(\d+)Mhz(\s*\*)?", line.strip())
        if not m:
            continue
        mx = int(m.group(1))  # list is ascending, so the last entry is max
        if m.group(2):
            cur = mx
    return cur, mx


def _read_hwmon_temps(hw: Path | None) -> dict[str, float]:
    """{edge/junction/mem/temp: celsius} from a GPU hwmon dir."""
    temps: dict[str, float] = {}
    if hw is None:
        return temps
    try:
        for entry in hw.iterdir():
            name = entry.name
            if not name.startswith("temp") or not name.endswith("_input"):
                continue
            try:
                value = int(_read_text(entry)) / 1000.0
            except ValueError:
                continue
            key = "temp"
            lbl = _read_text(entry.with_name(name[:-6] + "_label")).lower()
            if "edge" in lbl:
                key = "edge"
            elif "junction" in lbl:
                key = "junction"
            elif "mem" in lbl:
                key = "mem"
            temps[key] = value
    except OSError:
        pass
    return temps


def _read_hwmon_power(hw: Path | None) -> float | None:
    """GPU power draw in watts from hwmon power1_input/average, if present."""
    if hw is None:
        return None
    power_w = None
    for name in ("power1_average", "power1_input"):
        try:
            power_w = int(_read_text(hw / name)) / 1_000_000.0
            break
        except (OSError, ValueError):
            continue
    return power_w


def _read_hwmon_fan(hw: Path | None) -> tuple[int | None, int | None]:
    """(fan_rpm, fan_max) for a GPU hwmon, if present."""
    if hw is None:
        return None, None
    try:
        rpm = int(_read_text(hw / "fan1_input")) or None
    except ValueError:
        rpm = None
    try:
        mx = int(_read_text(hw / "fan1_max")) or None
    except ValueError:
        mx = None
    return rpm, mx


class GpuSampler:
    """Live GPU utilization/VRAM/temps/power/clocks across all three vendors.

    Resolves the primary GPU once (``_pick_gpu``), then dispatches to the
    vendor reader: AMD reads the amdgpu sysfs nodes directly; NVIDIA shells
    out to ``nvidia-smi`` (its only utilization source); Intel derives a busy
    percentage from the GT idle/RC6 residency delta and reads clocks from the
    per-GT sysfs nodes.
    """

    def __init__(self):
        self._target = _pick_gpu()
        self._hw = None
        self._intel_idle_path: Path | None = None
        self._prev_idle: int | None = None
        self._prev_t: float | None = None
        self._vendor = ""
        if self._target is not None:
            driver, dev = self._target
            self._vendor = _GPU_DRIVERS.get(driver, "")
            self._hw = _hwmon_for(dev)
            if driver in ("i915", "xe"):
                self._intel_idle_path = _find_attr(dev, _INTEL_IDLE)

    @property
    def vendor(self) -> str:
        return self._vendor

    @property
    def target(self):
        return self._target

    def _amd_sample(self, dev: Path) -> dict:
        def read(path) -> int | None:
            try:
                return int(_read_text(path))
            except ValueError:
                return None

        util = read(dev / "gpu_busy_percent") or 0
        vram_used = read(dev / "mem_info_vram_used")
        vram_total = read(dev / "mem_info_vram_total")
        core_mhz, core_max_mhz = _read_pp_dpm(dev, "pp_dpm_sclk")
        mem_mhz, mem_max_mhz = _read_pp_dpm(dev, "pp_dpm_mclk")
        fan_rpm, fan_max = _read_hwmon_fan(self._hw)
        return {
            "util_pct": float(util),
            "vram_used_gb": (vram_used or 0) / _GB,
            "vram_total_gb": (vram_total or 0) / _GB,
            "power_w": _read_hwmon_power(self._hw),
            "fan_rpm": fan_rpm,
            "fan_pct": round(100.0 * fan_rpm / fan_max) if (fan_rpm and fan_max) else None,
            "fan_max": fan_max,
            "temps": _read_hwmon_temps(self._hw),
            "core_mhz": core_mhz,
            "core_max_mhz": core_max_mhz,
            "mem_mhz": mem_mhz,
            "mem_max_mhz": mem_max_mhz,
            "name": _read_text(dev / "product_number") or "",
        }

    @staticmethod
    def _nvidia_sample() -> dict | None:
        """Utilization/VRAM/temp/power/fan/clocks from one nvidia-smi query.

        nvidia-smi is slow (~100ms+); cache the result briefly so the 1s GPU
        poll doesn't re-spawn it every tick.
        """
        now = time.monotonic()
        cached = _NVIDIA_CACHE.get("value")
        if cached is not None and now - _NVIDIA_CACHE["t"] < 2.0:
            return cached
        try:
            out = subprocess.run(
                _NVIDIA_QUERY, capture_output=True, text=True, timeout=3
            )
        except (subprocess.SubprocessError, OSError):
            return None
        if out.returncode != 0:
            return None
        line = out.stdout.splitlines()[0] if out.stdout.splitlines() else ""
        fields = [f.strip() for f in line.split(",")] if line else []
        if len(fields) != 8:
            return None

        def num(field: str):
            try:
                return float(field)
            except (TypeError, ValueError):
                return None

        util, mem_used, mem_total, temp = (num(f) for f in fields[:4])
        power, fan_pct, core, mem = (num(f) for f in fields[4:])
        result = {
            "util_pct": util,
            "vram_used_gb": (mem_used or 0) / 1024.0,
            "vram_total_gb": (mem_total or 0) / 1024.0,
            "power_w": power,
            "fan_rpm": None,          # nvidia-smi reports fan as a percent only
            "fan_pct": int(fan_pct) if fan_pct is not None else None,
            "fan_max": None,
            "temps": {"temp": temp} if temp is not None else {},
            "core_mhz": int(core) if core is not None else None,
            "core_max_mhz": None,
            "mem_mhz": int(mem) if mem is not None else None,
            "mem_max_mhz": None,
            "name": "",
        }
        _NVIDIA_CACHE["value"] = result
        _NVIDIA_CACHE["t"] = now
        return result

    def _intel_sample(self, dev: Path) -> dict:
        def read_int(path: Path | None):
            try:
                return int(_read_text(path))
            except (TypeError, ValueError):
                return None

        cur = read_int(_find_attr(dev, _INTEL_FREQ_CUR))
        mx = read_int(_find_attr(dev, _INTEL_FREQ_MAX))
        fan_rpm, fan_max = _read_hwmon_fan(self._hw)
        temps = _read_hwmon_temps(self._hw)
        util_pct = None
        if self._intel_idle_path is not None:
            now = time.monotonic()
            idle = read_int(self._intel_idle_path)
            if idle is not None:
                if self._prev_idle is not None and self._prev_t is not None:
                    delta = now - self._prev_t
                    if delta > 0:
                        idle_delta = idle - self._prev_idle
                        if idle_delta >= 0:
                            busy = 100.0 * (1.0 - idle_delta / 1000.0 / delta)
                            util_pct = max(0.0, min(busy, 100.0))
                self._prev_idle = idle
                self._prev_t = now

        return {
            "util_pct": util_pct,
            "vram_used_gb": None,   # Intel iGPU/Arc shares system memory
            "vram_total_gb": None,
            "power_w": _read_hwmon_power(self._hw),
            "fan_rpm": fan_rpm,
            "fan_pct": round(100.0 * fan_rpm / fan_max) if (fan_rpm and fan_max) else None,
            "fan_max": fan_max,
            "temps": temps,
            "core_mhz": cur,
            "core_max_mhz": mx,
            "mem_mhz": None,
            "mem_max_mhz": None,
            "name": "",
        }

    def sample(self) -> dict | None:
        """One normalized GPU sample across vendors, or None when unavailable."""
        if self._target is None:
            return None
        driver, dev = self._target
        if driver == "amdgpu":
            return self._amd_sample(dev)
        if driver == "nvidia":
            return self._nvidia_sample()
        if driver in ("i915", "xe"):
            return self._intel_sample(dev)
        return None


_GPU_SAMPLER = GpuSampler()


def gpu() -> dict | None:
    """GPU utilization/VRAM/temps/power/clocks for the primary GPU (any vendor)."""
    return _GPU_SAMPLER.sample()


# ── GPU static info (model / manufacturer / compute units / clocks) ──

def _rocminfo_gpu() -> dict | None:
    """Static GPU info from `rocminfo` (marketing name, vendor, CUs, max clock)."""
    try:
        out = subprocess.run(
            ["rocminfo"], capture_output=True, text=True, timeout=20
        )
    except (subprocess.SubprocessError, OSError):
        return None
    if out.returncode != 0:
        return None
    for block in re.split(r"(?m)^Agent \d+", out.stdout):
        dtype = re.search(r"Device Type:\s*(\S+)", block)
        if not dtype or dtype.group(1) != "GPU":
            continue
        info: dict = {}
        for key, field in (
            ("model", "Marketing Name:"),
            ("manufacturer", "Vendor Name:"),
            ("units", "Compute Unit:"),
            ("max_clock", "Max Clock Freq. (MHz):"),
        ):
            m = re.search(rf"^\s*{re.escape(field)}\s+(.+?)\s*$", block, re.M)
            if m and m.group(1).strip():
                info[key] = m.group(1).strip()
        return info or None
    return None


def _lspci_gpu(dev: Path | None = None) -> dict | None:
    """Fallback: manufacturer + model from ``lspci -nn`` (no rocminfo needed).

    When ``dev`` is given the line matching that GPU's PCI vendor/device IDs is
    returned so multi-GPU systems report the selected card, not the first one.
    """
    vid_want = did_want = None
    if dev is not None:
        vid_want = _read_text(dev / "vendor").replace("0x", "").lower()
        did_want = _read_text(dev / "device").replace("0x", "").lower()
    try:
        out = subprocess.run(
            ["lspci", "-nn"], capture_output=True, text=True, timeout=5
        )
    except (subprocess.SubprocessError, OSError):
        return None
    for line in out.stdout.splitlines():
        if not re.search(r"(?i)(vga compatible|3d controller|display controller)", line):
            continue
        m = re.search(r"\[([0-9A-Fa-f]{4}):([0-9A-Fa-f]{4})\]", line)
        vid = (m.group(1) if m else "").lower()
        did = (m.group(2) if m else "").lower()
        if vid_want and (vid != vid_want or (did_want and did != did_want)):
            continue
        desc = line.split(": ", 1)[1] if ": " in line else line
        desc = re.sub(r"\s*\[[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\].*$", "", desc).strip()
        vendor = re.match(r"([^\[\]]+)\[", desc)
        brand = vendor.group(1).strip() if vendor else ""
        model = desc[vendor.end():].strip() if vendor else desc
        return {
            "manufacturer": _GPU_VENDORS.get(vid, brand or "GPU"),
            "model": model or brand or line.strip(),
        }
    return None


def _gpu_fetch_static() -> dict | None:
    """Static GPU identity for the selected primary GPU (rocminfo -> lspci + sysfs)."""
    target = _GPU_SAMPLER.target
    dev = target[1] if target else None
    driver = target[0] if target else ""
    info = _rocminfo_gpu() or _lspci_gpu(dev)
    if info is None:
        return None
    if dev is not None:
        vendor_id = _read_text(dev / "vendor").lower()
        if vendor_id.startswith("0x") and vendor_id[2:] in _GPU_VENDORS:
            info.setdefault("manufacturer", _GPU_VENDORS[vendor_id[2:]])
        if driver == "amdgpu":
            _c, core_max_mhz = _read_pp_dpm(dev, "pp_dpm_sclk")
        else:
            mx = _find_attr(dev, _INTEL_FREQ_MAX)
            try:
                core_max_mhz = int(_read_text(mx))
            except (TypeError, ValueError):
                core_max_mhz = None
        if core_max_mhz is not None:
            info.setdefault("max_clock", core_max_mhz)
    try:
        info["units"] = int(info.get("units"))
    except (TypeError, ValueError):
        info["units"] = None
    try:
        info["max_clock"] = int(info.get("max_clock"))
    except (TypeError, ValueError):
        info["max_clock"] = None
    info["manufacturer"] = str(info.get("manufacturer") or "").strip() or "GPU"
    info["model"] = str(info.get("model") or "").strip()
    return info


def gpu_static(use_cache: bool = True) -> dict | None:
    """Static GPU info (model/manufacturer/units/max clock), cached.

    Fetched via rocminfo / lspci which need no root here; the result is cached
    in ~/.cache/hyprtk-bar/gpu.json. Call the fetch off the UI thread.
    """
    if use_cache:
        if _cache_fresh(GPU_CACHE, GPU_TTL):
            try:
                data = json.loads(GPU_CACHE.read_text())
                return data if isinstance(data, dict) else None
            except (OSError, json.JSONDecodeError):
                return None
        return None
    info = _gpu_fetch_static()
    if info:
        try:
            GPU_CACHE.parent.mkdir(parents=True, exist_ok=True)
            GPU_CACHE.write_text(json.dumps(info, indent=2))
        except OSError:
            pass
    return info


# ── processes ─────────────────────────────────────────────────────

def _read_pid_cpu(pid: int):
    """(comm, utime+stime) for a pid, or None."""
    try:
        data = Path("/proc", str(pid), "stat").read_text()
    except OSError:
        return None
    idx = data.rfind(")")
    if idx < 0:
        return None
    comm = data[data.find("(") + 1:idx]
    rest = data[idx + 2:].split()
    if len(rest) < 14:
        return None
    try:
        ticks = int(rest[11]) + int(rest[12])
    except ValueError:
        return None
    return comm, ticks


def _read_pid_rss(pid: int) -> int:
    """Resident set size in kB."""
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return 0


def _read_pid_uid(pid: int) -> int | None:
    """Real UID owner of a pid (from /proc/<pid>/status), or None."""
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("Uid:"):
                    parts = line.split()
                    return int(parts[1]) if len(parts) > 1 else None
    except (OSError, ValueError, IndexError):
        pass
    return None


def _read_pid_cmdline(pid: int) -> list[str]:
    """The process's argv (null-separated /proc/<pid>/cmdline), or []."""
    try:
        raw = Path("/proc", str(pid), "cmdline").read_bytes()
    except OSError:
        return []
    return [a for a in raw.decode("utf-8", "replace").split("\0") if a]


def _window_pids() -> set[int]:
    """PIDs owning windows on the Hyprland compositor (for app detection)."""
    try:
        out = subprocess.run(
            ["hyprctl", "clients", "-j"], capture_output=True, text=True, timeout=5
        ).stdout
        data = json.loads(out)
        return {int(w["pid"]) for w in data if isinstance(w, dict) and w.get("pid")}
    except Exception:
        return set()


# The previous poll's process sample, so top_processes() can diff against it
# instead of sleeping for a second sample (keeps the caller's thread unblocked).
_PROC_CACHE: dict = {}


def top_processes(n: int | None = None, window_pids: set[int] | None = None) -> list[dict]:
    """Every running process with its per-core CPU% (diff of two /proc samples).

    Returns *all* processes — idle ones included — so the caller can show a
    persistent list of running apps/processes instead of a top-N snapshot that
    drops anything currently quiet (e.g. an idle terminal). A process with no
    previous sample to diff against reports 0% CPU. Pass ``n`` to cap the
    result; the default is no cap.

    Each row carries ``pid``, ``name`` (comm), ``cpu``, ``mem`` (GB), ``uid``
    (owner), ``cmdline`` (argv) and ``is_app`` (owns a compositor window). Pass
    ``window_pids`` from the caller to avoid a duplicate hyprctl query.

    The previous poll's sample is cached (instead of ``sleep``-ing for a second
    sample), so this never blocks the caller.
    """
    ncpu = os.cpu_count() or 1
    if window_pids is None:
        window_pids = _window_pids()

    def sample() -> tuple[int, dict]:
        total = 1
        try:
            with open("/proc/stat") as f:
                parts = f.readline().split()
            total = sum(int(v) for v in parts[1:])
        except (OSError, ValueError):
            pass
        pids = {}
        try:
            for d in os.listdir("/proc"):
                if not d.isdigit():
                    continue
                pid = int(d)
                info = _read_pid_cpu(pid)
                if info:
                    pids[pid] = info
        except OSError:
            pass
        return max(total, 1), pids

    t2, p2 = sample()
    prev = _PROC_CACHE.get("sample")
    _PROC_CACHE["sample"] = (t2, p2)
    # With no baseline yet, treat every process as freshly seen (0% CPU) rather
    # than returning an empty list, so the first open already shows them all.
    t1, p1 = prev if prev is not None else (t2, p2)
    delta = max(t2 - t1, 1)

    rows = []
    for pid, (comm, ticks) in p2.items():
        first = p1.get(pid)
        cpu = 100.0 * ncpu * (ticks - first[1]) / delta if first is not None else 0.0
        if cpu < 0.0:
            cpu = 0.0
        rows.append(
            {
                "pid": pid,
                "name": comm,
                "cpu": cpu,
                "mem": _read_pid_rss(pid) * _KB / _GB,
                "uid": _read_pid_uid(pid),
                "cmdline": _read_pid_cmdline(pid),
                "is_app": pid in window_pids,
            }
        )
    rows.sort(key=lambda r: (-r["cpu"], r["name"].lower()))
    return rows[:n] if n else rows


# ── DIMM slots (SMBIOS via dmidecode) ────────────────────────────

def _dimm_size_gb(size: str) -> float | None:
    """Normalise a dmidecode Size field to GB; None when no module is present."""
    s = (size or "").strip().lower()
    if s in (
        "no module installed",
        "none",
        "not provided",
        "not specified",
        "unknown",
    ):
        return None
    m = re.search(r"([\d.]+)\s*(mib|gib|mb|gb)", s)
    if not m:
        return None
    val = float(m.group(1))
    if m.group(2) in ("mb", "mib"):
        val /= 1024.0
    return val


def parse_dmidecode(text: str) -> list[dict]:
    """Parse ``dmidecode -t 17`` output into a list of DIMM slot dicts.

    Each entry carries ``locator`` (the slot name), ``bank``, ``size`` (raw),
    ``size_gb`` and ``populated`` — empty slots report No Module Installed.
    """
    slots: list[dict] = []
    for block in text.split("Memory Device"):
        size = locator = bank = ""
        for line in block.splitlines():
            line = line.strip()
            if line.startswith("Size:"):
                size = line.split(":", 1)[1].strip()
            elif line.startswith("Locator:"):
                locator = line.split(":", 1)[1].strip()
            elif line.startswith("Bank Locator:"):
                bank = line.split(":", 1)[1].strip()
        if not locator:
            continue
        gb = _dimm_size_gb(size)
        slots.append(
            {
                "locator": locator,
                "bank": bank,
                "size": size or "Unknown",
                "size_gb": gb,
                "populated": gb is not None,
            }
        )
    return slots


def _dimm_cache_fresh() -> bool:
    try:
        return time.time() - DIMM_CACHE.stat().st_mtime < DIMM_TTL
    except OSError:
        return False


def _dimm_read_cache() -> list[dict] | None:
    try:
        data = json.loads(DIMM_CACHE.read_text())
        return data if isinstance(data, list) else None
    except (OSError, json.JSONDecodeError):
        return None


def _dimm_fetch() -> str:
    """Fetch ``dmidecode -t 17`` via sudo -n (fast, non-interactive) then pkexec."""
    for cmd in (
        ["sudo", "-n", "dmidecode", "-t", "17"],
        ["pkexec", "dmidecode", "-t", "17"],
    ):
        try:
            out = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
        except (subprocess.SubprocessError, OSError):
            continue
        if out.returncode == 0 and "Memory Device" in out.stdout:
            return out.stdout
    return ""


def dimm_slots(use_cache: bool = True) -> list[dict] | None:
    """DIMM slot list, or None when unavailable.

    With ``use_cache`` a fresh ~/.cache/hyprtk-bar/dimm.json is served directly
    (no prompt). Otherwise the data is fetched via sudo/pkexec and cached; the
    fetch may show a polkit password dialog, so call it off the UI thread.
    """
    if use_cache:
        if _dimm_cache_fresh():
            cached = _dimm_read_cache()
            if cached:
                return cached
        return None
    text = _dimm_fetch()
    if not text:
        return None
    slots = parse_dmidecode(text)
    try:
        DIMM_CACHE.parent.mkdir(parents=True, exist_ok=True)
        DIMM_CACHE.write_text(json.dumps(slots, indent=2))
    except OSError:
        pass
    return slots


# ── physical drives ──────────────────────────────────────────────

# lsblk is spawned once per poll (1s) while the Disks page is open; cache its
# result briefly so the per-second refresh doesn't re-spawn it every tick.
_DRIVES_TTL = 5.0
_DRIVES_CACHE: dict = {"value": None, "t": 0.0}


def drives() -> list[dict]:
    """Per-physical-disk info (size, available, type) via ``lsblk -J``.

    Each entry carries ``name``, ``model``, a ``type_key``/``type_label`` and
    a Nerd Font ``glyph`` for NVMe / HDD / SSD / USB / card readers, plus the
    raw ``size_b``/``used_b``/``free_b`` summed over the disk's mounted
    partitions (``mounted``). Empty USB readers report 0 bytes and ``mounted``
    False. Ordered by drive class (NVMe first, readers last).
    """
    now = time.monotonic()
    if _DRIVES_CACHE["value"] is not None and now - _DRIVES_CACHE["t"] < _DRIVES_TTL:
        return _DRIVES_CACHE["value"]
    try:
        out = subprocess.run(
            ["lsblk", "-J", "-b", "-o",
             "NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT,MODEL,ROTA,TRAN"],
            capture_output=True, text=True, timeout=5,
        )
        data = json.loads(out.stdout)
    except (subprocess.SubprocessError, OSError, json.JSONDecodeError):
        return []

    def _collect(node, used, free, mounts) -> None:
        for child in node.get("children") or []:
            mp = child.get("mountpoint")
            if mp:
                try:
                    usage = shutil.disk_usage(mp)
                    used.append(usage.used)
                    free.append(usage.free)
                    mounts.append(mp)
                except OSError:
                    pass
            _collect(child, used, free, mounts)

    result = []
    for block in data.get("blockdevices") or []:
        if block.get("type") != "disk":
            continue
        name = block.get("name") or ""
        try:
            size_b = int(block.get("size") or 0)
        except (TypeError, ValueError):
            size_b = 0
        rotational = str(block.get("rota")) in ("1", "True", "true")
        transport = str(block.get("tran") or "")
        model = str(block.get("model") or "").strip()

        used, free, mounts = [], [], []
        _collect(block, used, free, mounts)
        used_b = sum(used)
        free_b = sum(free)
        mounted = bool(mounts)
        is_root = "/" in mounts

        if transport == "nvme":
            type_key, type_label, glyph = "nvme", "NVMe SSD", "\uf2db"
        elif transport == "usb":
            if size_b == 0:
                type_key, type_label, glyph = "reader", "Card reader", "\uf287"
            elif rotational:
                type_key, type_label, glyph = "usb", "USB HDD", "\uf287"
            else:
                type_key, type_label, glyph = "usb", "USB SSD", "\uf287"
        elif rotational:
            type_key, type_label, glyph = "hdd", "HDD", "\U000f02ca"
        else:
            type_key, type_label, glyph = "ssd", "SSD", "\uf0e7"

        result.append(
            {
                "name": name,
                "model": model or name,
                "type_key": type_key,
                "type_label": type_label,
                "glyph": glyph,
                "size_b": size_b,
                "used_b": used_b,
                "free_b": free_b,
                "mounted": mounted,
                "is_root": is_root,
            }
        )

    order = {"nvme": 0, "hdd": 1, "ssd": 2, "usb": 3, "reader": 4}
    result.sort(key=lambda d: (order.get(d["type_key"], 9), d["name"]))
    _DRIVES_CACHE["value"] = result
    _DRIVES_CACHE["t"] = now
    return result