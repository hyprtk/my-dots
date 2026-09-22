"""CLI: flags for non-interactive use, TUI when run bare."""

from __future__ import annotations

import argparse
import os
import sys
import time

from . import __version__, core
from .core import SIZE_CHOICES, scan_isos  # noqa: F401  (re-exported)
from .ui import UI


def resolve_iso(explicit: str, runner: core.Runner) -> core.ISO:
    if explicit:
        return core.open_iso(explicit, runner)
    isos = scan_isos()
    if not isos:
        raise core.UsbError("no hyprtk ISO found - pass --iso <file>")
    return core.open_iso(isos[0], runner)


def resolve_target(runner: core.Runner, target: str, test_mode: bool) -> core.Device:
    return core.resolve_target(runner, target, test_mode)


def build_validated(iso: core.ISO, dev: core.Device, args, runner: core.Runner, test_mode: bool) -> core.Plan:
    core.validate_target(dev, iso.size, core.root_disk(runner), test_mode=test_mode)
    return core.build_plan(
        iso, dev,
        core.Options(persist=not args.no_persist, size=args.size, refresh=args.refresh, test_mode=test_mode),
    )


def writable_devices(runner: core.Runner, iso: core.ISO, test_mode: bool) -> list[core.Device]:
    root = core.root_disk(runner)
    out = []
    for d in core.list_devices(runner):
        try:
            core.validate_target(d, iso.size, root, test_mode=test_mode)
        except core.UsbError:
            continue
        out.append(d)
    return out


# ── non-interactive ────────────────────────────────────────────────────────


def run_cli(ui: UI, args, test_mode: bool) -> int:
    runner = core.ExecRunner()
    try:
        iso = resolve_iso(args.iso, runner)
        if not iso.looks_hyprtk():
            ui.warn(f"{iso.path} does not look like a hyprtk ISO (label {iso.label!r})")
        if not args.target:
            raise core.UsbError("no --target device given")
        dev = resolve_target(runner, args.target, test_mode)
        plan = build_validated(iso, dev, args, runner, test_mode)
    except core.UsbError as e:
        ui.err(str(e))
        return 1

    ui.show_plan(iso, dev, plan)
    if args.dry_run:
        ui.warn("dry run - nothing written")
        return 0
    if not args.yes and not ui.confirm(f"This ERASES {dev.path}. Proceed?", default=False):
        ui.info("aborted")
        return 0
    try:
        ui.run_write(iso, plan, runner)
    except (core.UsbError, OSError, Exception) as e:  # noqa: BLE001 - report and exit
        ui.err(str(e))
        return 1
    ui.ok('done - boot the stick and pick "Hyprtk live with persistence"')
    return 0


# ── TUI ────────────────────────────────────────────────────────────────────


def run_tui(ui: UI, test_mode: bool) -> int:
    runner = core.ExecRunner()
    ui.header("hyprtk-usb", "write a hyprtk ISO to a USB stick (+ persistence)")

    isos = scan_isos()
    if not isos:
        ui.err("no hyprtk ISO found in ~/Documents/Isos or ~")
        return 1
    if len(isos) == 1:
        iso_path = isos[0]
        ui.info(f"ISO: {iso_path}")
    else:
        iso_path = isos[ui.choose("Select the ISO to write", isos, default=0)]

    try:
        iso = core.open_iso(iso_path, runner)
        if not iso.looks_hyprtk():
            ui.warn(f"{iso.path} does not look like a hyprtk ISO (label {iso.label!r})")
        devs = writable_devices(runner, iso, test_mode)
        if not devs:
            ui.err("no writable disks found (all are mounted or back /)")
            return 1
        dev = devs[ui.choose("Select the target disk", [d.describe() for d in devs], default=0)]

        persist = ui.confirm("Add the hyprtk-persist partition?", default=True)
        refresh = False
        size = "rest"
        if persist:
            if dev.persist_partition() is not None:
                refresh = ui.confirm("Keep the existing hyprtk-persist partition?", default=True)
            if not refresh:
                size = SIZE_CHOICES[ui.choose("Persistence size", SIZE_CHOICES, default=0)]

        opts = core.Options(persist=persist, size=size, refresh=refresh, test_mode=test_mode)
        plan = core.build_plan(iso, dev, opts)
    except core.UsbError as e:
        ui.err(str(e))
        return 1

    ui.show_plan(iso, dev, plan)
    if not ui.confirm(f"This ERASES {dev.path}. Proceed?", default=False):
        ui.info("aborted")
        return 0

    try:
        ui.run_write(iso, plan, runner)
    except Exception as e:  # noqa: BLE001
        ui.err(str(e))
        return 1
    ui.ok('done - boot the stick and pick "Hyprtk live with persistence"')
    return 0


# ── entry ──────────────────────────────────────────────────────────────────


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="hyprtk-usb",
        description="Write a hyprtk ISO to a USB stick (+ optional persistence). Run with no flags for the TUI.",
    )
    p.add_argument("--iso", default="", help="ISO to write (default: newest hyprtk ISO)")
    p.add_argument("--target", default="", help="whole disk (e.g. /dev/sda); partitions are refused")
    p.add_argument("--size", default="rest", help="persistence size: 8G, 512M, 50%%, or rest")
    p.add_argument("--no-persist", action="store_true", help="write the ISO only")
    p.add_argument("--refresh", action="store_true", help="keep an existing hyprtk-persist partition")
    p.add_argument("--dry-run", action="store_true", help="print the plan; change nothing")
    p.add_argument("-y", "--yes", action="store_true", help="do not ask for confirmation")
    p.add_argument("--tui", action="store_true", help="force the interactive TUI")
    p.add_argument("--test", action="store_true", help="allow a regular-file target (testing)")
    p.add_argument("--version", action="version", version=f"hyprtk-usb {__version__}")
    return p


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    args = build_parser().parse_args(argv)
    test_mode = args.test or os.environ.get("HYPRTK_USB_TEST") == "1"

    # Writing needs root; re-exec under sudo like the shell script did.
    if not test_mode and not args.dry_run and os.geteuid() != 0:
        os.execvp("sudo", ["sudo", sys.executable, "-m", "hyprtk_usb", *argv])

    ui = UI()
    if args.tui or not argv:
        return run_tui(ui, test_mode)
    return run_cli(ui, args, test_mode)
