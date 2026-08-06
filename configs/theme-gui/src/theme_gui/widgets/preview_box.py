from gi.repository import Gtk


class PreviewBox(Gtk.Box):
    """A framed preview container for showing theme previews."""

    def __init__(self, title: str = "", **kwargs):
        super().__init__(orientation=Gtk.Orientation.VERTICAL, **kwargs)
        self.set_spacing(8)
        self.add_css_class("preview-box")

        if title:
            label = Gtk.Label(label=title)
            label.add_css_class("heading")
            label.set_xalign(0)
            self.append(label)

        self._frame = Gtk.Frame()
        self._frame.add_css_class("preview-frame")
        self._content_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        self._content_box.set_spacing(4)
        self._content_box.set_margin_top(8)
        self._content_box.set_margin_bottom(8)
        self._content_box.set_margin_start(8)
        self._content_box.set_margin_end(8)
        self._frame.set_child(self._content_box)
        self.append(self._frame)

    def set_content(self, widget: Gtk.Widget):
        self._content_box.set_child(widget)

    def set_css_background(self, css: str):
        self._frame.add_css_class(css)
