"""One-shot process actions for the system-monitor Apps page.

The Apps page's Launch / Kill / Force-kill buttons run this instead of talking
to the process tree from QML, so the signal/permission logic stays in the
toolkit-free backend (``monitor_data.kill_process`` / ``launch_process``).

Usage::

    python3 proc_action.py kill <pid> [--force]
    python3 proc_action.py launch <pid>

Exits 0 on success, 1 on failure, and prints a one-line JSON result.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from hyprtk_bar_qt import monitor_data
else:
    from . import monitor_data


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="process action for the bar's Apps page")
    sub = ap.add_subparsers(dest="action", required=True)

    kill = sub.add_parser("kill", help="terminate a process")
    kill.add_argument("pid", type=int)
    kill.add_argument("--force", action="store_true", help="SIGKILL instead of SIGTERM")

    launch = sub.add_parser("launch", help="re-launch a process from its argv")
    launch.add_argument("pid", type=int)

    args = ap.parse_args(argv)

    if args.action == "kill":
        ok = monitor_data.kill_process(args.pid, force=args.force)
    else:
        ok = monitor_data.launch_process(args.pid)

    print(json.dumps({"ok": bool(ok), "action": args.action, "pid": args.pid}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
