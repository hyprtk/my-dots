"""Core: the option model, builder argument construction and log helpers.

Everything here is pure (no GTK, no subprocess) so it can be unit-tested. The
GUI collects :class:`Options`; :func:`builder_args` turns them into the flags
``hyprtk-iso-builder.sh`` understands; the helper relays the builder's output as
one JSON object per line, using :func:`classify_level` and :func:`detect_stage`.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import date

BUILDER_NAME = "hyprtk-iso-builder.sh"


class BuildError(Exception):
    """A problem launching or locating the builder."""


# Builder stages, in order. Used for the progress bar; the long pole is "iso".
STAGES: list[tuple[str, str]] = [
    ("host", "Preparing the host"),
    ("source", "Locating the hyprtk source"),
    ("profile", "Assembling the archiso profile"),
    ("packages", "Merging the package list"),
    ("skel", "Building /etc/skel"),
    ("matuwall", "Building matuwall"),
    ("aur", "Building the AUR extras"),
    ("iso", "Building the ISO (mkarchiso)"),
]
_ORDER = {key: i for i, (key, _) in enumerate(STAGES)}


def stage_label(key: str) -> str:
    return dict(STAGES).get(key, key)


def stage_fraction(key: str) -> float:
    """Active-stage progress: the fraction of stages completed before `key`."""
    i = _ORDER.get(key)
    if i is None:
        return 0.0
    return i / len(STAGES)


@dataclass
class Options:
    hyprtk_dir: str = ""      # empty -> builder auto (~/hyprtk, else clone)
    iso_name: str = "hyprtk"
    iso_label: str = ""       # empty -> builder default HYPRTK_<YYYYMM>
    out_dir: str = ""         # empty -> the invoking user's home
    build_root: str = ""      # empty -> builder default /tmp/hyprtk-iso-build
    aur: bool = True
    matuwall: bool = True
    profile_only: bool = False
    keep_work: bool = False


def default_label() -> str:
    return "HYPRTK_" + date.today().strftime("%Y%m")


def builder_args(opts: Options) -> list[str]:
    """The builder flags for `opts` (``--yes`` is added by the helper)."""
    args: list[str] = []
    if opts.hyprtk_dir.strip():
        args += ["--hyprtk-dir", opts.hyprtk_dir.strip()]
    if opts.iso_name.strip():
        args += ["--iso-name", opts.iso_name.strip()]
    if opts.iso_label.strip():
        args += ["--iso-label", opts.iso_label.strip()]
    if opts.out_dir.strip():
        args += ["--out-dir", opts.out_dir.strip()]
    if opts.build_root.strip():
        args += ["--build-root", opts.build_root.strip()]
    if not opts.aur:
        args.append("--no-aur")
    if not opts.matuwall:
        args.append("--no-matuwall")
    if opts.profile_only:
        args.append("--profile-only")
    if opts.keep_work:
        args.append("--keep-work")
    return args


def validate(opts: Options) -> list[str]:
    """Return a list of human-readable problems (empty when the options are ok)."""
    errs: list[str] = []
    if not opts.iso_name.strip():
        errs.append("ISO name cannot be empty.")
    if opts.iso_label.strip() and len(opts.iso_label.strip()) > 32:
        errs.append("ISO label must be 32 characters or fewer.")
    return errs


# ── builder output parsing ─────────────────────────────────────────────────
_ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
_BOX_RE = re.compile(r"^[+=|]+$")


def strip_ansi(text: str) -> str:
    return _ANSI_RE.sub("", text)


def classify_level(line: str) -> str:
    """Bucket a builder line for the log view: err/warn/ok/info/title/text."""
    t = strip_ansi(line).strip()
    if not t:
        return "text"
    if t.startswith("\u2717"):          # ✗
        return "err"
    if t.startswith("!"):
        return "warn"
    if t.startswith("\u2713"):          # ✓
        return "ok"
    if t.startswith("\u2192"):          # →
        return "info"
    if _BOX_RE.match(t):
        return "title"
    return "text"


def _norm(line: str) -> str:
    """ANSI-stripped, marker-stripped line (drops a leading ✓/→/!/✗)."""
    t = strip_ansi(line).strip()
    for marker in ("\u2713", "\u2192", "\u2717", "!"):
        if t.startswith(marker):
            t = t[len(marker):].strip()
            break
    return t


def detect_stage(line: str) -> str | None:
    """Map a builder line to a stage key, or None if it starts no stage."""
    t = _norm(line)
    if not t:
        return None
    if "HYPRTK ARCH LINUX ISO BUILDER" in t or "Installing host build tools" in t:
        return "host"
    if t.startswith("hyprtk source:") or "No hyprtk source found locally" in t:
        return "source"
    if "Assembling archiso profile" in t:
        return "profile"
    if "package(s) to releng" in t:
        return "packages"
    if ("Vendoring trimmed hyprtk tree" in t
            or "Creating ~/.config symlinks" in t
            or "Packing /etc/skel" in t):
        return "skel"
    if "Building matuwall from source" in t:
        return "matuwall"
    if "AUR package(s)" in t:
        return "aur"
    if "Running mkarchiso" in t:
        return "iso"
    return None


def parse_iso_path(line: str) -> str | None:
    t = strip_ansi(line).strip().lstrip("\u2713").strip()
    m = re.match(r"^ISO:\s+(\S.*)$", t)
    return m.group(1).strip() if m else None


def parse_profile_path(line: str) -> str | None:
    t = strip_ansi(line).strip().lstrip("\u2713").strip()
    m = re.match(r"^Profile:\s+(\S.*)$", t)
    return m.group(1).strip() if m else None


def parse_size(line: str) -> str | None:
    t = strip_ansi(line).strip().lstrip("\u2713").strip()
    m = re.match(r"^Size:\s+(\S.*)$", t)
    return m.group(1).strip() if m else None
