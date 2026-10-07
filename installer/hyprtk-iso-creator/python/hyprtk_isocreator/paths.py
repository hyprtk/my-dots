"""Locate the Hyprtk-ISO-Creator checkout (the builder + its profile assets).

The builder is a bash script that reads ``airootfs/``, ``packages.hyprtk`` and
``aur-packages.txt`` relative to its own directory, so the GUI and its helper
need the *repo root*, not just the script. When run from a checkout that is the
package's ancestor; for an installed console script ``install.sh`` copies the
builder + those assets into ``~/.local/share/hyprtk-iso-creator/repo/`` and
records that path under ``~/.local/share/hyprtk-iso-creator/root``.
"""

from __future__ import annotations

import os
from pathlib import Path

BUILDER_NAME = "hyprtk-iso-builder.sh"
_STATE_DIR = "hyprtk-iso-creator"


def _recorded_root() -> Path | None:
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    marker = Path(base) / _STATE_DIR / "root"
    try:
        path = Path(marker.read_text().strip())
    except OSError:
        return None
    return path if (path / BUILDER_NAME).is_file() else None


def repo_root() -> Path:
    """The checkout holding ``hyprtk-iso-builder.sh``."""
    env = os.environ.get("HYPRTK_ISO_ROOT")
    if env and (Path(env) / BUILDER_NAME).is_file():
        return Path(env).resolve()

    here = Path(__file__).resolve()
    for parent in (here, *here.parents):
        if (parent / BUILDER_NAME).is_file():
            return parent

    recorded = _recorded_root()
    if recorded is not None:
        return recorded.resolve()

    cwd = Path.cwd()
    if (cwd / BUILDER_NAME).is_file():
        return cwd.resolve()

    raise FileNotFoundError(
        f"{BUILDER_NAME} not found - set HYPRTK_ISO_ROOT to the "
        "Hyprtk-ISO-Creator checkout"
    )


def builder_path() -> Path:
    return repo_root() / BUILDER_NAME
