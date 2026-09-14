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

import gi
gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
gi.require_version("GtkLayerShell", "0.1")

from gi.repository import Gdk, GLib, Gtk, GtkLayerShell  # noqa: E402

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
        self.set_accept_focus(True)
        self.connect("key-press-event", self._on_key)

        # ── header ────────────────────────────────────────────────
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        header.get_style_context().add_class("cliphist-header")
        title = Gtk.Label(label="Clipboard")
        title.get_style_context().add_class("notif-title")
        title.set_xalign(0)
        title.set_hexpand(True)
        header.pack_start(title, True, True, 0)

        self._clear_btn = Gtk.Button(label="Clear all")
        self._clear_btn.get_style_context().add_class("notif-clear")
        self._clear_btn.connect("clicked", self._on_clear)
        header.pack_start(self._clear_btn, False, False, 0)
        self.content.pack_start(header, False, False, 0)

        # ── search ────────────────────────────────────────────────
        self._search = Gtk.SearchEntry()
        self._search.set_placeholder_text("Search history…")
        self._search.get_style_context().add_class("cliphist-search")
        self._search.connect("search-changed", self._on_search)
        self.content.pack_start(self._search, False, False, 0)

        # ── list ──────────────────────────────────────────────────
        self._listbox = Gtk.ListBox()
        self._listbox.set_selection_mode(Gtk.SelectionMode.NONE)
        self._listbox.connect("row-activated", self._on_row_activated)
        scroller = Gtk.ScrolledWindow()
        scroller.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scroller.set_max_content_height(420)
        scroller.add(self._listbox)
        self.content.pack_start(scroller, True, True, 0)

        self._empty = Gtk.Label(label="Clipboard is empty")
        self._empty.get_style_context().add_class("cliphist-empty")
        self._empty.set_margin_top(16)
        self._empty.set_margin_bottom(16)

        self.content.show_all()

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
        for child in self._listbox.get_children():
            self._listbox.remove(child)
            child.destroy()

        filtered = self._entries
        needle = self._search.get_text().strip().lower()
        if needle:
            filtered = [e for e in self._entries if needle in e["info"].lower()]

        if not filtered:
            self._listbox.add(self._empty)
        for entry in filtered:
            self._listbox.add(self._make_row(entry))
        self._listbox.show_all()

    def _make_row(self, entry) -> Gtk.ListBoxRow:
        row = Gtk.ListBoxRow()
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        box.get_style_context().add_class("cliphist-row")

        label = Gtk.Label(label=entry["info"][:_MAX_PREVIEW])
        label.set_xalign(0)
        label.set_ellipsize(3)  # Pango.EllipsizeMode.END
        label.set_hexpand(True)
        label.get_style_context().add_class("cliphist-preview")
        box.pack_start(label, True, True, 0)

        delete = Gtk.Button(label="✕")
        delete.set_relief(Gtk.ReliefStyle.NONE)
        delete.get_style_context().add_class("cliphist-del")
        delete.connect("clicked", lambda _b, e=entry: self._on_delete(e))
        box.pack_start(delete, False, False, 0)

        row.add(box)
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
