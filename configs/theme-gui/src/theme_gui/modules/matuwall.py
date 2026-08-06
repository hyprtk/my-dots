from __future__ import annotations

import json

from gi.repository import Adw, Gtk

from .. import paths


class MatuwallPage(Adw.NavigationPage):
    def __init__(self, **kwargs):
        super().__init__(title="Matuwall", **kwargs)

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()
        toolbar.add_top_bar(header)

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        box.set_margin_top(12)
        box.set_margin_bottom(12)
        box.set_margin_start(12)
        box.set_margin_end(12)

        title = Gtk.Label(label="Matuwall Configuration")
        title.add_css_class("heading")
        title.set_xalign(0)
        box.append(title)

        self._config: dict = {}
        self._entries: dict[str, Adw.EntryRow] = {}
        self._switches: dict[str, Adw.SwitchRow] = {}

        # main section
        main_group = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._add_entry(main_group, "wallpaper_dir", "Wallpaper Directory")
        self._add_entry(main_group, "thumbnail_size", "Thumbnail Size")
        self._add_entry(main_group, "batch_size", "Batch Size")
        self._add_switch(main_group, "mouse_enabled", "Mouse Enabled")
        self._add_switch(main_group, "keep_ui_alive", "Keep UI Alive")
        box.append(main_group)

        # wall section
        wall_label = Gtk.Label(label="Wall Mode")
        wall_label.add_css_class("heading")
        wall_label.set_xalign(0)
        box.append(wall_label)

        wall_group = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._add_switch(wall_group, "wall_mode_only", "Wall Mode Only")
        self._add_entry(wall_group, "wall_awww_flags", "Awww Transition Flags")
        box.append(wall_group)

        # panel section
        panel_label = Gtk.Label(label="Panel Mode")
        panel_label.add_css_class("heading")
        panel_label.set_xalign(0)
        box.append(panel_label)

        panel_group = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        self._add_switch(panel_group, "panel_mode", "Panel Mode")
        self._add_entry(panel_group, "panel_edge", "Panel Edge")
        self._add_entry(panel_group, "panel_exclusive_zone", "Exclusive Zone")
        box.append(panel_group)

        # save button
        save_btn = Gtk.Button(label="Save Configuration")
        save_btn.add_css_class("suggested-action")
        save_btn.connect("clicked", self._save)
        box.append(save_btn)

        scroll = Gtk.ScrolledWindow()
        scroll.set_child(box)
        scroll.set_vexpand(True)

        toolbar.set_content(scroll)
        self.set_child(toolbar)

        self._load()

    def _add_entry(self, parent, key, title):
        row = Adw.EntryRow(title=title)
        parent.append(row)
        self._entries[key] = row

    def _add_switch(self, parent, key, title):
        row = Adw.SwitchRow(title=title)
        parent.append(row)
        self._switches[key] = row

    def _load(self):
        if not paths.MATUWALL_CONFIG.exists():
            return
        try:
            self._config = json.loads(paths.MATUWALL_CONFIG.read_text())
        except (json.JSONDecodeError, OSError):
            return

        for section in self._config.values():
            if not isinstance(section, dict):
                continue
            for key, val in section.items():
                if key in self._entries:
                    self._entries[key].set_text(str(val))
                if key in self._switches:
                    self._switches[key].set_active(bool(val))

    def _save(self, btn):
        for key, entry in self._entries.items():
            val = entry.get_text()
            for section in self._config.values():
                if isinstance(section, dict) and key in section:
                    # try to preserve type
                    orig = section[key]
                    if isinstance(orig, int):
                        section[key] = int(val) if val.isdigit() else orig
                    elif isinstance(orig, float):
                        try:
                            section[key] = float(val)
                        except ValueError:
                            pass
                    elif isinstance(orig, bool):
                        pass
                    else:
                        section[key] = val

        for key, switch in self._switches.items():
            val = switch.get_active()
            for section in self._config.values():
                if isinstance(section, dict) and key in section:
                    section[key] = val

        paths.MATUWALL_CONFIG.write_text(json.dumps(self._config, indent=2))
