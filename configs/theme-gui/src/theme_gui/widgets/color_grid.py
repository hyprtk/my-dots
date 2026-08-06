from gi.repository import Gtk, Gdk

from . import remove_all_children
from ..colors import get_color_name


class ColorGrid(Gtk.Grid):
    """Displays the 16-color pywal palette as a clickable grid."""

    def __init__(self, colors: dict[str, str] | None = None, **kwargs):
        super().__init__(**kwargs)
        self.set_column_spacing(6)
        self.set_row_spacing(6)
        self._buttons: list[Gtk.Button] = []
        self._providers: list[Gtk.CssProvider] = []
        self._callback = None
        if colors:
            self.set_colors(colors)

    def set_colors(self, colors: dict[str, str]):
        remove_all_children(self)
        self._buttons.clear()
        self._providers.clear()

        display = Gdk.Display.get_default()

        for i in range(16):
            key = f"color{i}"
            hex_val = colors.get(key, "#000000")
            name = get_color_name(i)

            btn = Gtk.Button()
            btn.set_tooltip_text(f"{name}\n{hex_val}")
            btn.add_css_class("flat")
            btn.set_size_request(48, 48)

            # per-button CSS provider — each gets its own so updates work
            provider = Gtk.CssProvider()
            css = f"button {{ background: {hex_val}; border-radius: 22px; min-width: 44px; min-height: 44px; }}"
            provider.load_from_data(css.encode())
            btn.get_style_context().add_provider(
                provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )
            self._providers.append(provider)

            idx = i
            btn.connect("clicked", lambda b, n=idx: self._on_click(n))
            self._buttons.append(btn)
            self.attach(btn, i % 8, i // 8, 1, 1)

    def _on_click(self, index: int):
        if self._callback:
            self._callback(index, f"color{index}")

    def connect_color_selected(self, callback):
        self._callback = callback
