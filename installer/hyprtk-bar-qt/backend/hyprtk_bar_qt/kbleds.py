"""Stream Caps Lock / Num Lock LED states as JSON lines.

Reads /sys/class/leds/*::{capslock,numlock}/brightness — the same source the
GTK bar's kbstate widget polled — so it works on Wayland.
"""

from __future__ import annotations

import argparse
import glob
import json
import time


def led_on(suffix: str) -> bool:
    """True if any LED whose name ends in ``suffix`` is lit."""
    for path in glob.glob(f"/sys/class/leds/*::{suffix}/brightness"):
        try:
            with open(path) as f:
                if f.read().strip() not in ("0", ""):
                    return True
        except OSError:
            continue
    return False


def sample() -> dict:
    return {"caps": led_on("capslock"), "num": led_on("numlock")}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="stream keyboard LED state as JSON lines")
    ap.add_argument("--interval", type=float, default=0.5, help="seconds between samples")
    args = ap.parse_args(argv)

    try:
        while True:
            print(json.dumps(sample()), flush=True)
            time.sleep(max(0.1, args.interval))
    except KeyboardInterrupt:
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
