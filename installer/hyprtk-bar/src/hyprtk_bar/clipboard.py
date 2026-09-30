"""In-bar clipboard history manager.

Replaces the old external ``cliphist.sh`` + rofi flow: a layer-shell dialogue
that lists the cliphist history, copies an entry on click, deletes a single
entry, and wipes the history — no rofi, no ``.rasi`` config.

Text entries show their preview; images show their size/format/dimensions and
copy with the correct MIME type.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · clipboard
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import re
import subprocess

from . import compat  # noqa: E402
from .compat import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

from .popup import Popup  # noqa: E402

log = logging.getLogger("hyprtk_bar.clipboard")

# "[[ binary data 79 KiB png 611x704 ]]" -> size/unit/format/w/h groups.
_IMAGE_RE = re.compile(
    r"\[\[\s*binary data\s+([0-9.]+)\s*([KMG]?i?B)\s+(\w+)\s+(\d+)x(\d+)\s*\]\]"
)
_MAX_PREVIEW = 400
_CLEAR_RESET_MS = 3000


def _run(args, timeout=8):
    try:
        return subprocess.run(args, capture_output=True, timeout=timeout)
    except (subprocess.SubprocessError, OSError) as exc:
        log.warning("cliphist %s failed: %s", args[0], exc)
        return None


def _list_entries():
    """cliphist list -> [{id, image?, info}]. `image` is the format (or None)."""
    proc = _run(["cliphist", "list"])
    entries = []
    if proc is None:
        return entries
    for line in proc.stdout.decode("utf-8", "replace").splitlines():
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
                "info": f"Image · {m.group(1)}{m.group(2)} {m.group(3)} "
                        f"{m.group(4)}x{m.group(5)}",
            })
        else:
            entries.append({"id": cid, "image": None, "info": preview})
    return entries


def _copy(entry):
    """Decode an entry and place it on the clipboard (text or image)."""
    cid = entry["id"]
    if not cid.isdigit():
        return False
    try:
        decode = subprocess.Popen(
            ["cliphist", "decode", cid], stdout=subprocess.PIPE
        )
        if entry["image"]:
            args = ["wl-copy", "--type", "image/" + entry["image"]]
        else:
            args = ["wl-copy"]
        subprocess.Popen(args, stdin=decode.stdout)
        decode.stdout.close()
        decode.wait()
        return True
    except (OSError, subprocess.SubprocessError) as exc:
        log.warning("cliphist copy %s failed: %s", cid, exc)
        return False


def _delete(cid):
    try:
        proc = subprocess.Popen(["cliphist", "delete"], stdin=subprocess.PIPE)
        proc.communicate((cid + "\n").encode("utf-8"))
        proc.wait()
    except (OSError, subprocess.SubprocessError) as exc:
        log.warning("cliphist delete %s failed: %s", cid, exc)


def _wipe():
    try:
        subprocess.Popen(["cliphist", "wipe"])
    except (OSError, subprocess.SubprocessError) as exc:
        log.warning("cliphist wipe failed: %s", exc)


class CliphistDialog(Popup):
    """Layer-shell clipboard history dialogue (list / copy / delete / wipe)."""

    def __init__(self, cfg: dict):
        super().__init__(cfg, cfg.get("position", "bottom"))
        self._cfg = cfg
        self._fixed_size = (420, 480)
        self._entries = []
        self._clear_armed = False
        self._clear_reset_id = None

        # The search entry needs keyboard input, which the Popup base disables.
        GtkLayerShell.set_keyboard_mode(self, GtkLayerShell.KeyboardMode.ON_DEMAND)
        compat.set_accept_focus(self, True)
        compat.on_key(self, self._on_key)

        # ── header ────────────────────────────────────────────────
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        compat.add_class(header, "cliphist-header")
        title = Gtk.Label(label="Clipboard")
        compat.add_class(title, "notif-title")
        title.set_xalign(0)
        title.set_hexpand(True)
        compat.pack_start(header, title, True, True, 0)

        self._clear_btn = Gtk.Button(label="Clear all")
        compat.add_class(self._clear_btn, "notif-clear")
        self._clear_btn.connect("clicked", self._on_clear)
        compat.pack_start(header, self._clear_btn, False, False, 0)
        compat.pack_start(self.content, header, False, False, 0)

        # ── search ────────────────────────────────────────────────
        self._search = Gtk.SearchEntry()
        self._search.set_placeholder_text("Search history…")
        compat.add_class(self._search, "cliphist-search")
        self._search.connect("search-changed", self._on_search)
        compat.pack_start(self.content, self._search, False, False, 0)

        # ── list ──────────────────────────────────────────────────
        self._listbox = Gtk.ListBox()
        self._listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._listbox.connect("row-activated", self._on_row_activated)
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_max_content_height(420)
        compat.add(scroller, self._listbox)
        compat.pack_start(self.content, scroller, True, True, 0)

        self._empty = Gtk.Label(label="Clipboard is empty")
        compat.add_class(self._empty, "cliphist-empty")
        self._empty.set_margin_top(16)
        self._empty.set_margin_bottom(16)

        compat.show_all(self.content)

    # ── popup lifecycle ───────────────────────────────────────────

    def show_above(self, widget) -> None:
        self._clear_armed = False
        self._clear_btn.set_label("Clear all")
        self._search.set_text("")
        self._refresh()
        super().show_above(widget)

    def _on_key(self, _window, event) -> bool:
        if event.keyval == Gdk.KEY_Escape:
            self.hide_popup()
            return True
        return False

    # ── data ──────────────────────────────────────────────────────

    def _refresh(self) -> None:
        self._entries = _list_entries()
        for child in compat.children(self._listbox):
            self._listbox.remove(child)
            compat.destroy(child)

        filtered = self._entries
        needle = self._search.get_text().strip().lower()
        if needle:
            filtered = [e for e in self._entries if needle in e["info"].lower()]

        if not filtered:
            compat.add(self._listbox, self._empty)
        for entry in filtered:
            compat.add(self._listbox, self._make_row(entry))
        compat.show_all(self._listbox)

    def _make_row(self, entry) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        compat.add_class(box, "cliphist-row")

        label = Gtk.Label(label=entry["info"][:_MAX_PREVIEW])
        label.set_xalign(0)
        label.set_ellipsize(3)  # Pango.EllipsizeMode.END
        label.set_hexpand(True)
        compat.add_class(label, "cliphist-preview")
        compat.pack_start(box, label, True, True, 0)

        delete = Gtk.Button(label="✕")
        compat.set_relief(delete)
        compat.add_class(delete, "cliphist-del")
        delete.connect("clicked", lambda _b, e=entry: self._on_delete(e))
        compat.pack_start(box, delete, False, False, 0)

        compat.add(row, box)
        return row

    # ── actions ───────────────────────────────────────────────────

    def _on_search(self, _entry) -> None:
        self._refresh()

    def _on_row_activated(self, _listbox, row) -> None:
        index = row.get_index()
        if index < 0 or index >= len(self._entries):
            return
        if _copy(self._entries[index]):
            self.hide_popup()

    def _on_delete(self, entry) -> None:
        _delete(entry["id"])
        self._refresh()

    def _on_clear(self, _btn) -> None:
        if not self._clear_armed:
            self._clear_armed = True
            self._clear_btn.set_label("Confirm?")
            self._clear_reset_id = GLib.timeout_add(_CLEAR_RESET_MS, self._reset_clear)
            return
        self._cancel_clear_reset()
        _wipe()
        self._clear_armed = False
        self._clear_btn.set_label("Clear all")
        self._refresh()

    def _reset_clear(self) -> bool:
        self._clear_reset_id = None
        self._clear_armed = False
        self._clear_btn.set_label("Clear all")
        return GLib.SOURCE_REMOVE

    def _cancel_clear_reset(self) -> None:
        if self._clear_reset_id is not None:
            GLib.source_remove(self._clear_reset_id)
            self._clear_reset_id = None
