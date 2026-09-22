"""Core logic: ISO/device discovery, planning, guardrails and writing.

Mirrors the Go implementation (internal/usb) so both behave identically. Every
external command goes through a Runner so the logic is testable without hardware.
"""

from __future__ import annotations

import json
import os
import subprocess
from dataclasses import dataclass, field
from typing import Callable, Optional

# 1 MiB expressed in 512-byte sectors.
DEFAULT_ALIGN = 2048
PERSIST_LABEL = "hyprtk-persist"
_LSBLK_COLS = "NAME,PATH,SIZE,TYPE,RM,TRAN,MODEL,MOUNTPOINT,PARTN,LABEL,START"


class UsbError(Exception):
    """A guardrail or planning failure."""


class Runner:
    """Runs external commands (injectable for tests)."""

    def output(self, *args: str) -> bytes:  # pragma: no cover - interface
        raise NotImplementedError

    def run(self, *args: str, stdin: str = "") -> None:  # pragma: no cover
        raise NotImplementedError


class ExecRunner(Runner):
    def output(self, *args: str) -> bytes:
        return subprocess.run(args, capture_output=True, check=True).stdout

    def run(self, *args: str, stdin: str = "") -> None:
        subprocess.run(args, input=stdin, text=True, capture_output=True, check=True)


# ── ISO ────────────────────────────────────────────────────────────────────


def scan_isos() -> list[str]:
    """hyprtk ISOs newest-first, from ~/Documents/Isos and ~."""
    home = os.path.expanduser("~")
    found: list[tuple[float, str]] = []
    for d in (os.path.join(home, "Documents", "Isos"), home):
        try:
            entries = os.listdir(d)
        except OSError:
            continue
        for name in entries:
            if not (name.startswith("hyprtk-") and name.endswith(".iso")):
                continue
            path = os.path.join(d, name)
            if os.path.isfile(path):
                found.append((os.path.getmtime(path), path))
    found.sort(reverse=True)
    return [p for _, p in found]


@dataclass
class ISO:
    path: str
    size: int
    label: str = ""

    def sectors(self) -> int:
        return (self.size + 511) // 512

    def looks_hyprtk(self) -> bool:
        return self.label.startswith("HYPRTK")


def open_iso(path: str, runner: Runner) -> ISO:
    if not os.path.exists(path):
        raise UsbError(f"iso: {path} not found")
    if os.path.isdir(path):
        raise UsbError(f"iso: {path} is a directory")
    size = os.stat(path).st_size
    label = ""
    try:
        label = runner.output("blkid", "-p", "-o", "value", "-s", "LABEL", path).decode().strip()
    except Exception:
        label = ""
    return ISO(path=path, size=size, label=label)


# ── devices ────────────────────────────────────────────────────────────────


@dataclass
class Partition:
    path: str
    size: int
    start: int
    label: str
    mountpoint: str
    num: int


@dataclass
class Device:
    path: str
    name: str
    size: int
    model: str = ""
    tran: str = ""
    removable: bool = False
    parts: list[Partition] = field(default_factory=list)

    def mounts(self) -> list[str]:
        return [p.mountpoint for p in self.parts if p.mountpoint]

    def describe(self) -> str:
        what = self.model.strip() or "disk"
        where = self.tran or "?"
        rm = ", removable" if self.removable else ""
        return f"{self.path} — {what}, {where}{rm}"

    def persist_partition(self) -> Optional[Partition]:
        for p in self.parts:
            if p.label == PERSIST_LABEL:
                return p
        return None


def list_devices(runner: Runner) -> list[Device]:
    raw = runner.output("lsblk", "-bJ", "-o", _LSBLK_COLS)
    data = json.loads(raw or b"{}")
    out: list[Device] = []
    for n in data.get("blockdevices", []):
        if n.get("type") not in ("disk", "loop"):
            continue
        parts = [
            Partition(
                path=c.get("path", ""),
                size=c.get("size") or 0,
                start=c.get("start") or 0,
                label=c.get("label") or "",
                mountpoint=c.get("mountpoint") or "",
                num=c.get("partn") or 0,
            )
            for c in (n.get("children") or [])
        ]
        out.append(
            Device(
                path=n.get("path", ""),
                name=n.get("name", ""),
                size=n.get("size") or 0,
                model=n.get("model") or "",
                tran=n.get("tran") or "",
                removable=bool(n.get("rm")),
                parts=parts,
            )
        )
    return out


def find_device(runner: Runner, path: str) -> Device:
    for d in list_devices(runner):
        if d.path == path:
            return d
    raise UsbError(f"target: {path} is not a whole-disk block device")


def resolve_target(runner: Runner, target: str, test_mode: bool = False) -> Device:
    """Find the target device, or — in test mode only — accept a regular file."""
    if test_mode and os.path.isfile(target):
        return Device(path=target, name=os.path.basename(target), size=os.stat(target).st_size)
    return find_device(runner, target)


def root_disk(runner: Runner) -> str:
    try:
        src = runner.output("findmnt", "-no", "SOURCE", "/").decode().strip()
        if not src:
            return ""
        pk = runner.output("lsblk", "-no", "PKNAME", src).decode().strip()
    except Exception:
        return ""
    return f"/dev/{pk}" if pk else ""


# ── planning ───────────────────────────────────────────────────────────────

MODE_NONE = "none"
MODE_FRESH = "fresh"
MODE_REFRESH = "refresh"


@dataclass
class Options:
    persist: bool = True
    size: str = "rest"
    refresh: bool = False
    align: int = DEFAULT_ALIGN
    test_mode: bool = False


@dataclass
class Plan:
    iso: ISO
    target_path: str
    target_size: int
    mode: str = MODE_NONE
    start_sectors: int = 0
    size_sectors: int = 0
    partition_num: int = 0
    partition_dev: str = ""
    test_mode: bool = False
    warnings: list[str] = field(default_factory=list)


def align_up(v: int, a: int) -> int:
    return v if a <= 1 else (v + a - 1) // a * a


def parse_size(spec: str, avail_sectors: int) -> int:
    s = (spec or "").strip().lower()
    if s in ("", "rest"):
        return avail_sectors
    if s.endswith("%"):
        pct = _int(s[:-1], spec)
        if not 1 <= pct <= 100:
            raise UsbError(_size_msg(spec))
        return avail_sectors * pct // 100
    if s.endswith("g"):
        return _int(s[:-1], spec) * 1024**3 // 512
    if s.endswith("m"):
        return _int(s[:-1], spec) * 1024**2 // 512
    return _int(s, spec)  # sectors


def _int(text: str, spec: str) -> int:
    try:
        n = int(text)
    except ValueError:
        raise UsbError(_size_msg(spec)) from None
    if n <= 0:
        raise UsbError(_size_msg(spec))
    return n


def _size_msg(spec: str) -> str:
    return f"bad size {spec!r}: use e.g. 8G, 512M, 50% or rest"


def next_free_part_num(dev: Device) -> int:
    used = {p.num for p in dev.parts}
    for n in range(1, 5):
        if n not in used:
            return n
    raise UsbError(f"no free partition slot on {dev.path} (MBR allows 4)")


def partition_path(device_path: str, n: int) -> str:
    for prefix in ("nvme", "mmcblk", "loop"):
        if prefix in device_path:
            return f"{device_path}p{n}"
    return f"{device_path}{n}"


def build_plan(iso: ISO, dev: Device, opts: Options) -> Plan:
    align = opts.align if opts.align > 0 else DEFAULT_ALIGN
    plan = Plan(iso=iso, target_path=dev.path, target_size=dev.size, test_mode=opts.test_mode)

    if not opts.persist:
        return plan

    total = dev.size // 512
    existing = dev.persist_partition()
    if existing is not None:
        start = existing.start // 512
        size = existing.size // 512
        if opts.refresh:
            if start < iso.sectors():
                raise UsbError(
                    f"existing {PERSIST_LABEL} partition overlaps the new ISO "
                    "- back it up and write fresh"
                )
            plan.mode = MODE_REFRESH
            plan.start_sectors = start
            plan.size_sectors = size
            plan.partition_num = existing.num
            plan.partition_dev = existing.path
            return plan
        plan.warnings.append(f"an existing {PERSIST_LABEL} partition will be replaced")

    plan.mode = MODE_FRESH
    plan.start_sectors = align_up(iso.sectors(), align)
    if plan.start_sectors > total - 1:
        raise UsbError(
            f"no room after the ISO for a persistence partition ({total - plan.start_sectors} sectors free)"
        )
    avail = total - plan.start_sectors
    size = parse_size(opts.size, avail)
    size = size // align * align
    if size < align:
        raise UsbError(f"persistence partition too small (need at least {align * 512 // 1024 // 1024} MiB)")
    if size > avail:
        raise UsbError(f"persistence size exceeds the free space ({avail * 512 // 1024 // 1024} MiB)")
    num = next_free_part_num(dev)
    plan.size_sectors = size
    plan.partition_num = num
    plan.partition_dev = partition_path(dev.path, num)
    return plan


# ── guardrails ─────────────────────────────────────────────────────────────


def validate_target(dev: Device, iso_size: int, root: str, test_mode: bool = False) -> None:
    if not dev.path:
        raise UsbError("target: no device selected")
    if dev.path == root and not test_mode:
        raise UsbError(f"refusing to write the disk backing / ({dev.path})")
    if dev.size <= iso_size:
        raise UsbError(f"target ({dev.size} bytes) is smaller than the ISO ({iso_size} bytes)")
    mounts = dev.mounts()
    if mounts:
        raise UsbError(f"{dev.path} has mounted partitions ({', '.join(mounts)}) - unmount them first")


# ── writing ────────────────────────────────────────────────────────────────


@dataclass
class Progress:
    stage: str
    written: int = 0
    total: int = 0


def write(iso: ISO, plan: Plan, runner: Runner, on_progress: Optional[Callable[[Progress], None]] = None) -> None:
    def report(p: Progress) -> None:
        if on_progress:
            on_progress(p)

    report(Progress("copy", 0, iso.size))
    copy_iso(iso.path, plan.target_path, lambda n: report(Progress("copy", n, iso.size)))
    _reread(runner, plan.target_path)

    if plan.mode == MODE_NONE:
        report(Progress("done"))
        return

    report(Progress("partition"))
    append_partition(runner, plan.target_path, plan.start_sectors, plan.size_sectors)
    _reread(runner, plan.target_path)

    if plan.mode == MODE_FRESH and not plan.test_mode:
        report(Progress("format"))
        runner.run("mkfs.ext4", "-F", "-L", PERSIST_LABEL, plan.partition_dev)

    report(Progress("done"))


def append_partition(runner: Runner, target: str, start: int, size: int) -> None:
    runner.run("sfdisk", "--append", target, stdin=f"start={start}, size={size}, type=83\n")


def _reread(runner: Runner, target: str) -> None:
    try:
        runner.run("blockdev", "--rereadpt", target)
    except Exception:
        pass  # harmless for a regular-file test target


def copy_iso(src: str, dst: str, on_written: Optional[Callable[[int], None]] = None) -> None:
    """Stream the ISO onto the target. No O_TRUNC: a device is written in place."""
    fd = os.open(dst, os.O_WRONLY | os.O_CREAT, 0o644)
    written = 0
    with open(src, "rb") as s, os.fdopen(fd, "wb") as d:
        while True:
            buf = s.read(4 << 20)
            if not buf:
                break
            d.write(buf)
            written += len(buf)
            if on_written:
                on_written(written)
        d.flush()
        os.fsync(d.fileno())
