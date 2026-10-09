"""Audio levels for the visualizer desktop widget.

Runs ``cava`` in raw-ascii mode (a small config is written to the cache dir) and
streams one normalised frame per line as JSON — ``{"levels": [0..1, ...]}``.
When cava is absent it falls back to a synthetic animation so the widget still
renders. Toolkit-free; the QML widget draws the frames.

Ported from the GTK bar's ``desktop/visualizer.py`` (the cava plumbing).
"""

from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import stat
import subprocess
import sys
import threading
import time
from pathlib import Path

CAVA_CONF_PATH = Path.home() / ".cache" / "hyprtk-bar-qt" / "cava-hyprtk.conf"


def resolve_binary(name: str) -> str | None:
    """Resolve a configured binary to a safe absolute path, or None."""
    name = str(name or "").strip()
    if not name:
        return None
    path = os.path.abspath(os.path.expanduser(name)) if os.sep in name else (shutil.which(name) or "")
    if not path:
        return None
    try:
        info = os.stat(path)
    except OSError:
        return None
    if not stat.S_ISREG(info.st_mode) or not os.access(path, os.X_OK):
        return None
    if info.st_mode & 0o022:
        return None
    return path


def write_cava_config(bars: int, fps: int) -> Path:
    CAVA_CONF_PATH.parent.mkdir(parents=True, exist_ok=True)
    CAVA_CONF_PATH.write_text(
        "[general]\n"
        f"bars = {max(8, int(bars))}\n"
        f"framerate = {max(15, int(fps))}\n"
        "autosens = 1\n"
        "lower_cutoff_freq = 50\n"
        "higher_cutoff_freq = 10000\n\n"
        "[output]\n"
        "method = raw\n"
        "raw_target = /dev/stdout\n"
        "data_format = ascii\n"
        "ascii_max_range = 100\n"
        "channels = mono\n\n"
        "[smoothing]\n"
        "monstercat = 1\n"
        "waves = 0\n"
        "noise_reduction = 0.77\n"
    )
    return CAVA_CONF_PATH


def parse_frame(line: str) -> list[float]:
    """One raw-ascii cava frame (``"0;12;34;…"``) -> normalised levels (0..1)."""
    values = []
    for token in line.strip().split(";"):
        token = token.strip()
        if not token:
            continue
        try:
            values.append(max(0.0, min(1.0, int(token) / 100.0)))
        except ValueError:
            return []
    return values


def synthetic_frame(t: float, bars: int) -> list[float]:
    """A smooth synthetic spectrum (0..1) for systems without cava."""
    out = []
    for i in range(bars):
        base = 0.5 + 0.5 * math.sin(t * 2.0 + i * 0.5)
        wobble = 0.3 * math.sin(t * 5.0 + i * 1.3)
        out.append(max(0.0, min(1.0, base * 0.6 + wobble * 0.3)))
    return out


class CavaSource:
    def __init__(self, binary: str, bars: int, fps: int):
        self._binary = binary
        self._bars = bars
        self._fps = fps
        self._proc: subprocess.Popen | None = None
        self._queue: list[list[float]] = []
        self._lock = threading.Lock()
        self._thread: threading.Thread | None = None
        self._stop = threading.Event()

    def start(self) -> bool:
        try:
            conf = write_cava_config(self._bars, self._fps)
            self._proc = subprocess.Popen(
                [self._binary, "-p", str(conf)],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1,
            )
        except (OSError, subprocess.SubprocessError):
            self._proc = None
            return False
        self._thread = threading.Thread(target=self._read, daemon=True)
        self._thread.start()
        return True

    def _read(self) -> None:
        assert self._proc is not None and self._proc.stdout is not None
        for line in self._proc.stdout:
            if self._stop.is_set():
                break
            frame = parse_frame(line)
            if frame:
                with self._lock:
                    self._queue = frame

    def latest(self) -> list[float] | None:
        with self._lock:
            return list(self._queue) if self._queue else None

    def stop(self) -> None:
        self._stop.set()
        if self._proc is not None:
            try:
                self._proc.terminate()
            except OSError:
                pass


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="stream cava audio levels as JSON lines")
    ap.add_argument("--bars", type=int, default=48)
    ap.add_argument("--fps", type=int, default=60)
    ap.add_argument("--binary", default="cava")
    ap.add_argument("--source", choices=("auto", "cava", "synthetic"), default="auto",
                    help="auto = cava if available else synthetic; synthetic forces the fallback")
    args = ap.parse_args(argv)

    bars = max(8, args.bars)
    interval = 1.0 / max(15, args.fps)

    resolved = None if args.source == "synthetic" else resolve_binary(args.binary)
    source = CavaSource(resolved, bars, args.fps) if resolved else None
    started = source.start() if source is not None else False

    t0 = time.monotonic()
    try:
        while True:
            frame = source.latest() if started and source is not None else None
            if frame is None:
                frame = synthetic_frame(time.monotonic() - t0, bars)
            print(json.dumps({"levels": frame}), flush=True)
            time.sleep(interval)
    except KeyboardInterrupt:
        return 0
    finally:
        if source is not None:
            source.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
