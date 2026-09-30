#!/usr/bin/env python3
"""hyprtk-bar E2E orchestrator.

Runs the pytest suite once per GTK stack (the ported tree is dual-stack via
``HYPRTK_GTK``), collects a JSON report for each, then renders the merged
``e2e-output.html`` with a GTK3/GTK4 parity column.

Invoked by ``tools/e2e/in-container.sh``; run directly only inside the image.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
LAYERS = {"0": "test_l0_static.py", "1": "test_l1_construct.py",
          "2": "test_l2_settings.py", "3": "test_l3_functional.py",
          "4": "test_l4_visual.py", "5": "test_l5_smoke.py"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stack", choices=["3", "4", "both"], default="both")
    ap.add_argument("--layer", choices=list(LAYERS), default=None)
    # Everything after a literal `--` is passed through to pytest verbatim
    # (argparse routes it into the positional); our own flags go before it.
    ap.add_argument("pytest_args", nargs="*", help="extra args passed to pytest")
    args = ap.parse_args()

    report_dir = Path(os.environ.get("E2E_REPORT_DIR", HERE / "report"))
    report_dir.mkdir(parents=True, exist_ok=True)

    if args.layer:
        target = str(HERE / "tests" / LAYERS[args.layer])
    else:
        target = str(HERE / "tests")

    stacks = ["3", "4"] if args.stack == "both" else [args.stack]
    rc_all = 0
    for stack in stacks:
        out_json = report_dir / f"report-gtk{stack}.json"
        env = dict(os.environ)
        env["HYPRTK_GTK"] = stack
        env["E2E_STACK"] = stack
        env["E2E_JSON"] = str(out_json)
        env["PYTHONPATH"] = f"{REPO / 'src'}{os.pathsep}{HERE}{os.pathsep}" + env.get("PYTHONPATH", "")
        home = Path("/tmp") / f"e2e-home-gtk{stack}"
        home.mkdir(parents=True, exist_ok=True)
        env["HOME"] = str(home)
        env["XDG_CONFIG_HOME"] = str(home / ".config")
        # gtk4-layer-shell must be linked before libwayland-client; a bare
        # `python -m` run (unlike the installed launcher) needs the preload.
        preload = ("/usr/lib/libgtk4-layer-shell.so" if stack == "4"
                   else "/usr/lib/libgtk-layer-shell.so")
        if os.path.exists(preload):
            env["LD_PRELOAD"] = preload
        cmd = [sys.executable, "-m", "pytest", target, "-q", "-p", "no:cacheprovider",
               "--tb=short", "--no-header", *args.pytest_args]
        print(f"\n===== GTK{stack} :: {' '.join(cmd)} =====", flush=True)
        rc = subprocess.run(cmd, cwd=str(REPO), env=env).returncode
        rc_all |= rc

    from reporter import render  # local import: HERE is on PYTHONPATH
    out = render(report_dir, stacks)
    print(f"\n== wrote {out} ==")
    return rc_all


if __name__ == "__main__":
    sys.exit(main())
