"""Wallpaper folder scanning + thumbnail cache + apply for the Qt themer.

The Wallpaper page lists images from a directory. Loading full-resolution
wallpapers into QML was slow (tens of seconds for a large folder), so ``scan``
serves small cached thumbnails instead; the cache lives in the Qt bar's own
tree (``~/.cache/hyprtk-bar-qt/thumbs``) and is pre-built on install. Applying
one runs the hyprtk ``wallpaper-colors.sh`` script (sets the wallpaper and
regenerates pywal). Toolkit-free and testable.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import subprocess
from pathlib import Path

IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp", ".jxl", ".avif"}
CURRENT = Path.home() / ".cache" / "current-wallpaper.png"

try:
    from .paths import QT_CACHE
except ImportError:  # run as a script (python3 wallpapers.py)
    from paths import QT_CACHE

THUMB_DIR = QT_CACHE / "thumbs"
THUMB_WIDTH = 400


def scan(directory: str) -> list[str]:
    """Absolute paths of image files directly in ``directory`` (sorted)."""
    try:
        entries = Path(directory).expanduser().iterdir()
    except OSError:
        return []
    return sorted(
        str(p.resolve())
        for p in entries
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS
    )


def thumb_path(src: str) -> Path:
    """Deterministic cached-thumbnail path for *src* (changes when the file does)."""
    try:
        st = os.stat(src)
        key = f"{src}:{st.st_mtime_ns}:{st.st_size}:{THUMB_WIDTH}"
    except OSError:
        key = f"{src}:{THUMB_WIDTH}"
    return THUMB_DIR / (hashlib.sha1(key.encode()).hexdigest()[:20] + ".jpg")


def _make_thumb(src: str, dst: Path) -> bool:
    """Render a small JPEG thumbnail for *src*. PIL, else ImageMagick, else vips."""
    try:
        from PIL import Image  # type: ignore

        with Image.open(src) as im:
            try:
                im.draft("RGB", (THUMB_WIDTH, THUMB_WIDTH))
            except Exception:
                pass
            im = im.convert("RGB")
            im.thumbnail((THUMB_WIDTH, THUMB_WIDTH))
            im.save(dst, "JPEG", quality=82)
        return True
    except Exception:
        pass
    for cmd in (
        ["magick", src, "-resize", f"{THUMB_WIDTH}x{THUMB_WIDTH}>", str(dst)],
        ["convert", src, "-resize", f"{THUMB_WIDTH}x{THUMB_WIDTH}>", str(dst)],
        ["vipsthumbnail", src, "--size", str(THUMB_WIDTH), "-o", str(dst)],
    ):
        try:
            subprocess.run(cmd, check=True, timeout=30,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            return True
        except (OSError, subprocess.SubprocessError):
            continue
    return False


def ensure_thumb(src: str) -> str | None:
    """Return the (cached) thumbnail path for *src*, generating it if needed."""
    if not os.path.isfile(src):
        return None
    dst = thumb_path(src)
    if dst.is_file():
        return str(dst)
    try:
        THUMB_DIR.mkdir(parents=True, exist_ok=True)
    except OSError:
        return None
    return str(dst) if _make_thumb(src, dst) else None


def scan_items(directory: str, with_thumbs: bool = True) -> list[dict]:
    """``[{"path": full, "thumb": cached-or-None}]`` for ``scan`` + thumbnails."""
    out = []
    for path in scan(directory):
        thumb = ensure_thumb(path) if with_thumbs else None
        out.append({"path": path, "thumb": thumb})
    return out


def build_thumbs(directory: str) -> int:
    """Pre-generate thumbnails for every image in *directory*; returns the count."""
    count = 0
    for path in scan(directory):
        if ensure_thumb(path):
            count += 1
    return count


def current() -> str | None:
    return str(CURRENT) if CURRENT.is_file() else None


def _wallpaper_script() -> Path | None:
    try:
        from .paths import QT_SCRIPTS
    except ImportError:  # run as a script (python3 wallpapers.py)
        from paths import QT_SCRIPTS
    home = Path.home()
    for candidate in (
        QT_SCRIPTS / "wallpaper-colors.sh",
        home / "hyprtk" / "configs" / "hypr" / "scripts" / "wallpaper-colors.sh",
    ):
        if candidate.is_file():
            return candidate
    return None


def apply(image: str) -> bool:
    """Set ``image`` as the wallpaper and regenerate pywal."""
    if not image or not os.path.isfile(image):
        return False
    script = _wallpaper_script()
    if script is None:
        return False
    try:
        subprocess.Popen(["bash", str(script), image], start_new_session=True)
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def random_image(directory: str) -> str | None:
    """One random image from ``directory`` (or None if there are none)."""
    images = scan(directory)
    return random.choice(images) if images else None


def random_apply(directory: str) -> str | None:
    """Pick a random wallpaper from *directory* and apply it (wallpaper + pywal).

    Returns the chosen image path on success, else None.
    """
    image = random_image(directory)
    return image if image and apply(image) else None


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="wallpaper scanning + thumbnails + apply")
    sub = ap.add_subparsers(dest="action", required=True)
    scan_p = sub.add_parser("scan")
    scan_p.add_argument("directory", nargs="?", default=str(Path.home() / "Pictures" / "Wallpapers"))
    scan_p.add_argument("--no-thumbs", action="store_true")
    bt = sub.add_parser("build-thumbs")
    bt.add_argument("directory", nargs="?", default=str(Path.home() / "Pictures" / "Wallpapers"))
    sub.add_parser("current")
    apply_p = sub.add_parser("apply")
    apply_p.add_argument("image")
    rand_p = sub.add_parser("random")
    rand_p.add_argument("directory", nargs="?", default=str(Path.home() / "Pictures" / "Wallpapers"))
    args = ap.parse_args(argv)

    if args.action == "scan":
        print(json.dumps({"images": scan_items(args.directory, with_thumbs=not args.no_thumbs)}))
        return 0
    if args.action == "build-thumbs":
        print(json.dumps({"count": build_thumbs(args.directory)}))
        return 0
    if args.action == "current":
        print(json.dumps({"current": current()}))
        return 0
    if args.action == "random":
        chosen = random_apply(args.directory)
        print(json.dumps({"ok": bool(chosen), "path": chosen or ""}))
        return 0 if chosen else 1
    ok = apply(args.image)
    print(json.dumps({"ok": bool(ok)}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
