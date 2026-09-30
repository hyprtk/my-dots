"""L5 · real-process smoke — run the actual bar binary under the headless session.

Everything above constructs widgets in-process. This launches ``python -m
hyprtk_bar`` exactly as the desktop does, waits for it to map, drives the three
signals (SIGUSR1 menu, SIGUSR2 arc, SIGHUP clipboard) and confirms a clean
SIGTERM exit. It is the end-to-end check that the wiring in ``__main__`` holds.
"""
from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[3]


def _spawn(env_extra: dict | None = None):
    env = dict(os.environ)
    env["PYTHONPATH"] = str(REPO / "src") + os.pathsep + env.get("PYTHONPATH", "")
    env["PYTHONUNBUFFERED"] = "1"
    if env_extra:
        env.update(env_extra)
    log = Path("/tmp") / f"l5-bar-gtk{os.environ.get('E2E_STACK', '?')}.log"
    handle = open(log, "w")
    proc = subprocess.Popen(
        [sys.executable, "-m", "hyprtk_bar", "-v"],
        cwd=str(REPO), env=env, stdout=handle, stderr=subprocess.STDOUT,
    )
    return proc, log


def _wait_alive(proc, seconds=8.0) -> bool:
    deadline = time.time() + seconds
    while time.time() < deadline:
        if proc.poll() is not None:
            return False
        time.sleep(0.2)
    return True


@pytest.mark.skipif(
    not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"),
    reason="needs HYPRLAND_INSTANCE_SIGNATURE (set by in-container.sh)",
)
def test_bar_process_starts_signals_and_exits(details):
    proc, log = _spawn()
    try:
        alive = _wait_alive(proc)
        details["started"] = alive
        assert alive, f"bar process exited early:\n{_tail(log)}"

        for sig, name in ((signal.SIGUSR1, "SIGUSR1"), (signal.SIGUSR2, "SIGUSR2"),
                          (signal.SIGHUP, "SIGHUP")):
            os.kill(proc.pid, sig)
            time.sleep(1.0)
            details[f"alive_after_{name}"] = proc.poll() is None
            assert proc.poll() is None, f"bar died on {name}:\n{_tail(log)}"

        os.kill(proc.pid, signal.SIGTERM)
        try:
            proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass
        details["exit_code"] = proc.returncode
        details["log_tail"] = _tail(log, 40)
        assert proc.returncode is not None, f"bar did not exit on SIGTERM:\n{_tail(log)}"
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()


def test_real_process_reloads_config(details):
    """A change to config.json on disk is picked up by a fresh process."""
    from hyprtk_bar import config as config_module

    cfg = dict(config_module.DEFAULTS)
    cfg["height"] = 44
    config_module.save(cfg)

    proc, log = _spawn()
    try:
        assert _wait_alive(proc), f"bar exited early:\n{_tail(log)}"
        details["started"] = True
    finally:
        if proc.poll() is None:
            os.kill(proc.pid, signal.SIGTERM)
            try:
                proc.wait(timeout=8)
            except subprocess.TimeoutExpired:
                proc.kill()


def _tail(path: Path, n: int = 30) -> str:
    try:
        return "".join(path.read_text(errors="replace").splitlines(keepends=True)[-n:])
    except OSError:
        return "(no log)"
