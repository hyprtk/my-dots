"""One-shot DIMM-slot reader for the system monitor's Memory page.

SMBIOS needs root, so the fetch goes through ``monitor_data.dimm_slots`` (which
tries ``sudo -n`` then ``pkexec``) and the result is cached to
``~/.cache/hyprtk-bar-qt/dimm.json``. The QML calls this off the UI thread.

Usage::

    python3 dimm.py            # cached only (no prompt; may be empty)
    python3 dimm.py --fetch    # may prompt via pkexec, then caches

Prints one JSON line: ``{"ok": bool, "slots": [...]}``.
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
    ap = argparse.ArgumentParser(description="read DIMM slots via SMBIOS/dmidecode")
    ap.add_argument("--fetch", action="store_true", help="fetch (may prompt) and cache")
    args = ap.parse_args(argv)

    slots = monitor_data.dimm_slots(use_cache=not args.fetch)
    print(json.dumps({"ok": slots is not None, "slots": slots or []}))
    return 0 if slots else 1


if __name__ == "__main__":
    raise SystemExit(main())
