"""Privileged write helper.

The GUI runs unprivileged and shells out to this module via ``pkexec`` for the
single operation that needs root: writing the ISO and creating the partition.
Keeping the elevation to this one step means the GTK app never runs as root and
isn't affected by pkexec's stripped environment.

It re-derives the plan (and re-runs the guardrails) from the ISO + target, so a
target change between review and write cannot slip through. Progress is emitted
as one JSON object per line on stdout.
"""

from __future__ import annotations

import argparse
import json
import sys

from . import core


def _emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="hyprtk-usb-helper")
    p.add_argument("--iso", required=True)
    p.add_argument("--target", required=True)
    p.add_argument("--size", default="rest")
    p.add_argument("--no-persist", action="store_true")
    p.add_argument("--refresh", action="store_true")
    p.add_argument("--test", action="store_true")
    args = p.parse_args(argv)

    runner = core.ExecRunner()
    try:
        iso = core.open_iso(args.iso, runner)
        dev = core.resolve_target(runner, args.target, args.test)
        core.validate_target(dev, iso.size, core.root_disk(runner), test_mode=args.test)
        plan = core.build_plan(
            iso, dev,
            core.Options(
                persist=not args.no_persist,
                size=args.size,
                refresh=args.refresh,
                test_mode=args.test,
            ),
        )
    except core.UsbError as e:
        print(f"error: {e}", file=sys.stderr, flush=True)
        return 1

    _emit({"stage": "plan", "mode": plan.mode, "partition_dev": plan.partition_dev})
    try:
        core.write(iso, plan, runner, lambda pr: _emit({"stage": pr.stage, "written": pr.written, "total": pr.total}))
    except Exception as e:  # noqa: BLE001 - report to the GUI
        print(f"error: {e}", file=sys.stderr, flush=True)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
