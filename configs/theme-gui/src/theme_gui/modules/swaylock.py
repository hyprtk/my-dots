from __future__ import annotations

import os
import shutil
from pathlib import Path

from gi.repository import Adw, Gtk

from .. import paths
from ..colors import read_swaylock_config, write_swaylock_config
from ..widgets.color_button import ColorButton


class SwaylockPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(title="Swaylock", **kwargs)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        # pywal mode section
        wal_frame = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        wal_title = Gtk.Label(label="Pywal Mode")
        wal_title.add_css_class("heading")
        wal_title.set_xalign(0)
        wal_frame.append(wal_title)

        wal_desc = Gtk.Label(
            label="Copy pywal-generated colors to swaylock config. "
            "This syncs the lock screen with your current wallpaper palette."
        )
        wal_desc.set_xalign(0)
        wal_desc.set_wrap(True)
        wal_frame.append(wal_desc)

        apply_wal_btn = Gtk.Button(label="Apply Pywal Colors")
        apply_wal_btn.add_css_class("suggested-action")
        apply_wal_btn.connect("clicked", self._apply_pywal)
        wal_frame.append(apply_wal_btn)
        box.append(wal_frame)

        sep = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        box.append(sep)

        # manual mode section
        manual_title = Gtk.Label(label="Manual Color Editor")
        manual_title.add_css_class("heading")
        manual_title.set_xalign(0)
        box.append(manual_title)

        self._color_buttons: dict[str, ColorButton] = {}
        color_grid = Gtk.Grid()
        color_grid.set_column_spacing(12)
        color_grid.set_row_spacing(8)

        color_fields = [
            ("ring-color", "Ring (idle)"),
            ("ring-clear-color", "Ring (clear)"),
            ("ring-wrong-color", "Ring (wrong)"),
            ("ring-ver-color", "Ring (verifying)"),
            ("ring-caps-lock-color", "Ring (caps lock)"),
            ("inside-color", "Inside (idle)"),
            ("inside-clear-color", "Inside (clear)"),
            ("inside-wrong-color", "Inside (wrong)"),
            ("inside-ver-color", "Inside (verifying)"),
            ("key-hl-color", "Key highlight"),
            ("text-color", "Text"),
            ("bs-hl-color", "Backspace highlight"),
        ]

        for i, (key, label) in enumerate(color_fields):
            lbl = Gtk.Label(label=label)
            lbl.set_xalign(0)
            lbl.set_size_request(140, -1)
            color_grid.attach(lbl, 0, i, 1, 1)

            cb = ColorButton()
            cb.connect_color_changed(lambda btn, hex_val, k=key: self._on_color_change(k, hex_val))
            self._color_buttons[key] = cb
            color_grid.attach(cb, 1, i, 1, 1)

        box.append(color_grid)

        # save button
        save_btn = Gtk.Button(label="Save Manual Config")
        save_btn.add_css_class("suggested-action")
        save_btn.connect("clicked", self._save_manual)
        box.append(save_btn)

        # settings section
        sep2 = Gtk.Separator(orientation=Gtk.Orientation.HORIZONTAL)
        box.append(sep2)

        settings_title = Gtk.Label(label="Indicator Settings")
        settings_title.add_css_class("heading")
        settings_title.set_xalign(0)
        box.append(settings_title)

        self._indicator_radius = Adw.EntryRow(title="Indicator Radius")
        self._indicator_thickness = Adw.EntryRow(title="Indicator Thickness")
        self._fade_in = Adw.EntryRow(title="Fade-in (seconds)")
        self._effect = Adw.EntryRow(title="Effect (e.g. effect-pixelate=5)")
        box.append(self._indicator_radius)
        box.append(self._indicator_thickness)
        box.append(self._fade_in)
        box.append(self._effect)

        save_settings_btn = Gtk.Button(label="Save Settings")
        save_settings_btn.add_css_class("suggested-action")
        save_settings_btn.connect("clicked", self._save_settings)
        box.append(save_settings_btn)

        scroll = Gtk.ScrolledWindow()
        scroll.set_child(box)
        scroll.set_vexpand(True)

        toolbar.set_content(scroll)
        self.set_child(toolbar)

        self._load()

    def _load(self):
        config = read_swaylock_config()
        for key, cb in self._color_buttons.items():
            val = config.get(key, "#ffffff")
            # ensure # prefix for CSS
            if not val.startswith("#"):
                val = f"#{val}"
            cb.set_color(val)

        self._indicator_radius.set_text(config.get("indicator-radius", "200"))
        self._indicator_thickness.set_text(config.get("indicator-thickness", "20"))
        self._fade_in.set_text(config.get("fade-in", "1"))

        # find effect line
        for key in config:
            if key.startswith("effect-"):
                self._effect.set_text(f"{key}={config[key]}")
                break

    def _on_color_change(self, key: str, hex_val: str):
        pass  # live preview could go here

    def _apply_pywal(self, btn):
        src = paths.WAL_CACHE / "colors-swaylock.conf"
        dst = paths.SWAYLOCK_CONFIG
        if src.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(str(src), str(dst))
            self._load()

    def _save_manual(self, btn):
        config = read_swaylock_config()
        for key, cb in self._color_buttons.items():
            # swaylock config uses hex without # prefix
            config[key] = cb.get_color().lstrip("#")
        write_swaylock_config(config)

    def _save_settings(self, btn):
        config = read_swaylock_config()
        config["indicator-radius"] = self._indicator_radius.get_text()
        config["indicator-thickness"] = self._indicator_thickness.get_text()
        config["fade-in"] = self._fade_in.get_text()

        # clear old effects
        for key in list(config.keys()):
            if key.startswith("effect-"):
                del config[key]

        effect_text = self._effect.get_text().strip()
        if "=" in effect_text:
            k, _, v = effect_text.partition("=")
            config[k] = v

        write_swaylock_config(config)
