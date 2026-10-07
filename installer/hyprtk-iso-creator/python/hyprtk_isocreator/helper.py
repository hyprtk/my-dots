"""Privileged build helper.

The GTK app runs unprivileged and shells out to this module via ``pkexec`` for
the one operation that needs root: ``mkarchiso`` (and the profile/AUR staging
around it). Keeping elevation to this step means the app never runs as root and
isn't affected by pkexec's stripped environment.

This runs the *same* ``hyprtk-iso-builder.sh`` a user would run, as the invoking
user (via ``SUDO_USER``), and relays its output as one JSON object per line on
stdout: ``log`` / ``stage`` / ``done`` / ``error`` events.
"""

from __future__ import annotations

import argparse
import json
import os
import pwd
import subprocess
import sys

from . import core

_ERR_TAIL = 8


def _emit(obj: dict) -> None:
    print(json.dumps(obj), flush=True)


def _resolve_user(explicit: str) -> str:
    if explicit:
        return explicit
    uid = os.environ.get("PKEXEC_UID")
    if uid:
        try:
            return pwd.getpwuid(int(uid)).pw_name
        except (ValueError, KeyError):
            pass
    return os.environ.get("SUDO_USER") or ""


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="hyprtk-iso-creator-helper")
    p.add_argument("--builder", required=True, help="absolute path to hyprtk-iso-builder.sh")
    p.add_argument("--user", default="", help="the invoking user (default: PKEXEC_UID)")
    args, extra = p.parse_known_args(argv)

    if extra and extra[0] == "--":
        extra = extra[1:]

    if not os.path.isfile(args.builder):
        _emit({"type": "error", "message": f"builder not found: {args.builder}"})
        return 2

    user = _resolve_user(args.user)
    env = dict(os.environ)
    if user:
        # The builder derives the real (non-root) user from SUDO_USER, so it
        # vendors/AUR-builds and writes the ISO as that user, not root.
        env["SUDO_USER"] = user

    cmd = ["bash", args.builder, "--yes", *extra]
    try:
        proc = subprocess.Popen(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
            env=env,
        )
    except OSError as e:
        _emit({"type": "error", "message": str(e)})
        return 1

    assert proc.stdout is not None
    iso = size = profile = ""
    err_tail: list[str] = []
    for raw in proc.stdout:
        line = raw.rstrip("\n").rstrip("\r")
        text = core.strip_ansi(line)
        if not text.strip():
            continue
        level = core.classify_level(line)
        _emit({"type": "log", "level": level, "text": text})
        stage = core.detect_stage(line)
        if stage:
            _emit({"type": "stage", "name": stage, "label": core.stage_label(stage)})

        found_iso = core.parse_iso_path(line)
        if found_iso:
            iso = found_iso
        found_profile = core.parse_profile_path(line)
        if found_profile:
            profile = found_profile
        found_size = core.parse_size(line)
        if found_size:
            size = found_size

        if level == "err":
            err_tail.append(text.strip())
            del err_tail[:-_ERR_TAIL]

    rc = proc.wait()
    if rc != 0:
        message = "\n".join(err_tail) or f"{core.BUILDER_NAME} failed (exit {rc})"
        _emit({"type": "error", "message": message})
        return rc
    _emit({"type": "done", "iso": iso, "size": size, "profile": profile})
    return 0


if __name__ == "__main__":
    sys.exit(main())
