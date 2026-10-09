"""cliphist-backed clipboard history for the Qt bar.

The in-bar clipboard dialogue (``surface/Clipboard.qml``) drives this: it runs
``list`` to populate the panel, ``copy <id>`` to put an entry back on the
clipboard (text or image via ``wl-copy``), ``delete <id>`` per row, and ``wipe``
for "Clear all". Toolkit-free and testable (see ``parse_list``).
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess

# "[[ binary data 79 KiB png 611x704 ]]" -> size/unit/format/w/h groups.
_IMAGE_RE = re.compile(
    r"\[\[\s*binary data\s+([0-9.]+)\s*([KMG]?i?B)\s+(\w+)\s+(\d+)x(\d+)\s*\]\]"
)
_MAX_PREVIEW = 400


def parse_list(text: str) -> list[dict]:
    """Parse ``cliphist list`` output into ``[{id, image, info}]``.

    ``image`` is the image format (e.g. ``png``) or None for text entries.
    """
    entries = []
    for line in text.splitlines():
        if "\t" not in line:
            continue
        cid, preview = line.split("\t", 1)
        if not cid.isdigit():
            continue
        m = _IMAGE_RE.search(preview)
        if m:
            entries.append({
                "id": cid,
                "image": m.group(3).lower(),
                "info": f"Image \u00b7 {m.group(1)}{m.group(2)} {m.group(3)} "
                        f"{m.group(4)}x{m.group(5)}",
            })
        else:
            entries.append({"id": cid, "image": None, "info": preview[:_MAX_PREVIEW]})
    return entries


def _run(args, timeout=8):
    try:
        return subprocess.run(args, capture_output=True, timeout=timeout)
    except (subprocess.SubprocessError, OSError):
        return None


def list_entries() -> list[dict]:
    proc = _run(["cliphist", "list"])
    if proc is None:
        return []
    return parse_list(proc.stdout.decode("utf-8", "replace"))


def copy_entry(cid: str, image: str | None) -> bool:
    """Decode an entry and place it on the clipboard (text or image)."""
    if not str(cid).isdigit():
        return False
    try:
        decode = subprocess.Popen(["cliphist", "decode", str(cid)], stdout=subprocess.PIPE)
        args = ["wl-copy", "--type", "image/" + image] if image else ["wl-copy"]
        copy = subprocess.Popen(args, stdin=decode.stdout)
        decode.stdout.close()
        decode.wait()
        return copy.wait() == 0
    except (OSError, subprocess.SubprocessError):
        return False


def delete_entry(cid: str) -> bool:
    try:
        proc = subprocess.Popen(["cliphist", "delete"], stdin=subprocess.PIPE)
        proc.communicate((str(cid) + "\n").encode("utf-8"))
        return proc.wait() == 0
    except (OSError, subprocess.SubprocessError):
        return False


def wipe() -> bool:
    try:
        return subprocess.run(["cliphist", "wipe"], capture_output=True, timeout=8).returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="cliphist clipboard actions")
    sub = ap.add_subparsers(dest="action", required=True)
    sub.add_parser("list")
    copy = sub.add_parser("copy")
    copy.add_argument("id")
    copy.add_argument("--image", default="")
    delete = sub.add_parser("delete")
    delete.add_argument("id")
    sub.add_parser("wipe")
    args = ap.parse_args(argv)

    if args.action == "list":
        print(json.dumps({"entries": list_entries()}))
        return 0
    if args.action == "copy":
        ok = copy_entry(args.id, args.image or None)
    elif args.action == "delete":
        ok = delete_entry(args.id)
    else:
        ok = wipe()
    print(json.dumps({"ok": bool(ok)}))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
