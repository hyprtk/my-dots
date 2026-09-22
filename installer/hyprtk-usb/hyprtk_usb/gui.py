"""GTK 3 front end for hyprtk-usb.

The GUI runs unprivileged and drives the same ``core`` backend as the CLI. The
single privileged operation — the write — is performed by ``hyprtk_usb.helper``
launched through ``pkexec``, so the GTK app never runs as root and isn't subject
to pkexec's stripped environment.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")

import json  # noqa: E402
import os  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import sys  # noqa: E402
import threading  # noqa: E402

from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import __version__, core  # noqa: E402
from .ui import human_bytes, load_palette  # noqa: E402

SIZE_CHOICES = core.SIZE_CHOICES
TEST_MODE = os.environ.get("HYPRTK_USB_TEST") == "1"


def _helper_command() -> list[str]:
    """The command that performs the privileged write (before elevation)."""
    exe = shutil.which("hyprtk-usb-helper")
    if exe:
        return [exe]
    # Run in place: hand the package's parent to PYTHONPATH so it imports as
    # root too (the user's site-packages isn't on root's sys.path).
    parent = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    envbin = shutil.which("env") or "/usr/bin/env"
    py = sys.executable or "python3"
    return [envbin, f"PYTHONPATH={parent}", py, "-m", "hyprtk_usb.helper"]


def _elevate(cmd: list[str]) -> list[str]:
    if os.geteuid() == 0 or TEST_MODE:
        return cmd
    pkexec = shutil.which("pkexec")
    if not pkexec:
        raise core.UsbError("pkexec not found - run the app as root or install polkit")
    return [pkexec, *cmd]


class Window(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application) -> None:
        super().__init__(application=app, title="hyprtk-usb")
        self.set_default_size(720, 600)
        self.p = load_palette()
        self.runner = core.ExecRunner()

        self.step = "iso"
        self.iso_path = ""
        self.devices: list[core.Device] = []
        self.target = ""
        self.persist = True
        self.size = "rest"
        self.refresh = False

        # Match hyprtk-bar's floating dialogs: no client-side decorations (the CSD
        # headerbar caused artifacts along the top edge). The compositor draws the
        # pywal border + rounding; the panel is frosted at the bar's opacity.
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_app_paintable(True)
        screen = self.get_screen()
        visual = screen.get_rgba_visual() if screen is not None else None
        if visual is not None:
            self.set_visual(visual)

        # Scope our stylesheet to this window; prefer the dark GTK variant so the
        # combo popups (separate windows) stay dark too.
        self.get_style_context().add_class("hyprtk-usb")
        settings = Gtk.Settings.get_default()
        if settings is not None:
            settings.set_property("gtk-application-prefer-dark-theme", True)
        self._apply_css()

        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.panel.get_style_context().add_class("panel")
        self.add(self.panel)
        self.panel.pack_start(self._header_row(), False, False, 0)
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        self.box.set_border_width(18)
        self.panel.pack_start(self.box, True, True, 0)
        self.show_step()

    def _header_row(self) -> Gtk.Widget:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.get_style_context().add_class("header")
        title = Gtk.Label(label="hyprtk-usb", xalign=0)
        title.get_style_context().add_class("title")
        title.set_hexpand(True)
        row.pack_start(title, True, True, 0)
        if self.p.theme_name:
            theme_lbl = Gtk.Label(label=self.p.theme_name, xalign=1)
            theme_lbl.get_style_context().add_class("dim")
            row.pack_start(theme_lbl, False, False, 0)

        close = Gtk.Button(label="\u00d7")
        close.get_style_context().add_class("close")
        close.set_relief(Gtk.ReliefStyle.NONE)
        close.set_focus_on_click(False)
        close.connect("clicked", lambda *_: self.close())
        row.pack_end(close, False, False, 0)

        # No CSD titlebar, so let the header drag the window.
        row.add_events(Gdk.EventMask.BUTTON_PRESS_MASK)
        row.connect(
            "button-press-event",
            lambda w, e: self.begin_move_drag(e.button, int(e.x_root), int(e.y_root), e.time),
        )
        return row

    # ── theming ────────────────────────────────────────────────────────
    def _apply_css(self) -> None:
        p = self.p
        # Mirrors hyprtk-bar's semantic tokens (assets/style.css): a pywal-driven
        # dark frosted panel with mauve (color5) accents and cyan (color6) surface
        # tints. Scoped to `.hyprtk-usb` so it never restyles other windows.
        css = f"""
@define-color bg {p.bg};
@define-color fg {p.fg};
@define-color dim {p.dim};
@define-color accent {p.accent};
@define-color accent_alt {p.accent2};
@define-color err {p.err};
@define-color warn {p.warn};

/* The compositor draws the pywal border + rounding (like every other hyprtk
   floating window); the panel is frosted at the bar theme's opacity. */
.hyprtk-usb {{ background-color: transparent; color: @fg; border: none; }}

.hyprtk-usb .panel {{ background-color: alpha(@bg, {p.opacity:.3f}); }}

.hyprtk-usb .header {{ padding: 10px 10px 2px 16px; }}
.hyprtk-usb button.close {{
    background-image: none; background-color: transparent;
    border: none; box-shadow: none;
    color: @dim; font-size: 15pt; padding: 0 8px; min-height: 0;
}}
.hyprtk-usb button.close:hover {{ color: @err; }}

.hyprtk-usb label {{ color: @fg; }}
.hyprtk-usb label.title {{ color: @accent; font-weight: bold; font-size: 15pt; }}
.hyprtk-usb label.dim {{ color: @dim; }}
.hyprtk-usb label.warn {{ color: @warn; }}
.hyprtk-usb label.err {{ color: @err; }}
.hyprtk-usb label.ok {{ color: @accent_alt; }}

/* The GTK theme paints a background-image/shadow over any background-color, so
   reset them (the bar does the same inside its menu). */
.hyprtk-usb button {{
    background-image: none; box-shadow: none; text-shadow: none;
    background-color: alpha(@accent_alt, 0.10);
    color: @fg;
    border: 1px solid alpha(@accent_alt, 0.25);
    border-radius: 10px;
    padding: 6px 14px;
}}
.hyprtk-usb button:hover {{ background-color: alpha(@accent_alt, 0.18); }}
.hyprtk-usb button.suggested-action {{
    background-color: alpha(@accent, 0.85);
    color: #ffffff;
    border: 1px solid alpha(@accent, 0.95);
    font-weight: bold;
}}
.hyprtk-usb button.suggested-action:hover {{ background-color: @accent; }}

.hyprtk-usb entry, .hyprtk-usb combobox button {{
    background-image: none; box-shadow: none;
    background-color: alpha(@accent_alt, 0.08);
    color: @fg;
    border: 1px solid alpha(@accent_alt, 0.25);
    border-radius: 10px;
    padding: 5px 10px;
}}
.hyprtk-usb combobox arrow {{ color: @accent; }}

/* Switches: the GTK theme paints the trough/slider with a background-image and
   shadow, which sits over any background-color — reset them (else a light
   square shows around the switch). */
.hyprtk-usb switch {{
    background-image: none; box-shadow: none;
    background-color: alpha(@accent_alt, 0.20);
    border: 1px solid alpha(@accent_alt, 0.30);
    border-radius: 12px;
    min-width: 40px; min-height: 22px;
}}
.hyprtk-usb switch:checked {{
    background-image: none; box-shadow: none;
    background-color: @accent;
    border-color: @accent;
}}
.hyprtk-usb switch slider {{
    background-image: none; box-shadow: none;
    background-color: #ffffff;
    border: none;
    border-radius: 8px;
    min-width: 16px; min-height: 16px;
    margin: 2px;
}}

.hyprtk-usb progressbar trough {{
    background-color: alpha(@accent_alt, 0.12);
    border-radius: 8px;
    min-height: 10px;
}}
.hyprtk-usb progressbar progress {{ background-color: @accent; border-radius: 8px; }}
"""
        provider = Gtk.CssProvider()
        provider.load_from_data(css.encode())
        screen = Gdk.Screen.get_default()
        if screen is not None:
            Gtk.StyleContext.add_provider_for_screen(
                screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

    # ── widgets ────────────────────────────────────────────────────────
    def _clear(self) -> None:
        for child in self.box.get_children():
            self.box.remove(child)

    def _title(self, text: str, sub: str = "") -> None:
        lbl = Gtk.Label(label=text, xalign=0)
        lbl.get_style_context().add_class("title")
        self.box.pack_start(lbl, False, False, 0)
        if sub:
            s = Gtk.Label(label=sub, xalign=0)
            s.get_style_context().add_class("dim")
            s.set_line_wrap(True)
            self.box.pack_start(s, False, False, 0)

    def _buttons(self, back: bool, forward: tuple[str, str] | None) -> None:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.END)
        row.set_margin_top(6)
        if back:
            b = Gtk.Button(label="Back")
            b.connect("clicked", lambda *_: self.go_back())
            row.pack_end(b, False, False, 0)
        if forward:
            label, nxt = forward
            b = Gtk.Button(label=label)
            b.get_style_context().add_class("suggested-action")
            b.connect("clicked", lambda *_: self.advance(nxt))
            row.pack_end(b, False, False, 0)
        self.box.pack_end(row, False, False, 0)

    # ── steps ──────────────────────────────────────────────────────────
    def show_step(self) -> None:
        self._clear()
        getattr(self, f"_step_{self.step}")()
        # Widgets added after the window is mapped are not visible until shown;
        # the first page works because ApplicationWindow.show_all() runs once.
        self.box.show_all()

    def go_back(self) -> None:
        self.step = {"device": "iso", "options": "device", "review": "options"}.get(self.step, "iso")
        self.show_step()

    def advance(self, nxt: str) -> None:
        self.step = nxt
        self.show_step()

    def _step_iso(self) -> None:
        self._title("Select the ISO", "The hyprtk ISO to write to the USB stick.")
        isos = core.scan_isos()
        combo = Gtk.ComboBoxText()
        for path in isos:
            combo.append_text(path)
        if isos:
            combo.set_active(0)
        combo.connect("changed", lambda c: self._set_iso(c.get_active_text() or ""))
        if isos:
            self.iso_path = isos[0]
        self.box.pack_start(combo, False, False, 0)

        browse = Gtk.Button(label="Browse…")
        browse.set_halign(Gtk.Align.START)
        browse.connect("clicked", lambda *_: self._browse_iso())
        self.box.pack_start(browse, False, False, 0)

        if not isos:
            w = Gtk.Label(label="No hyprtk ISO found in ~/Documents/Isos or ~.", xalign=0)
            w.get_style_context().add_class("warn")
            self.box.pack_start(w, False, False, 0)

        self._buttons(back=False, forward=("Continue", "device"))

    def _browse_iso(self) -> None:
        dlg = Gtk.FileChooserDialog(
            title="Select ISO", transient_for=self, action=Gtk.FileChooserAction.OPEN
        )
        dlg.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Open", Gtk.ResponseType.OK)
        f = Gtk.FileFilter()
        f.set_name("ISO images")
        f.add_pattern("*.iso")
        dlg.add_filter(f)
        if dlg.run() == Gtk.ResponseType.OK:
            self._set_iso(dlg.get_filename() or "")
        dlg.destroy()

    def _set_iso(self, path: str) -> None:
        self.iso_path = path
        self.devices = []
        self.target = ""

    def _step_device(self) -> None:
        self._title("Select the target disk", "Whole disks only — the stick is erased.")
        try:
            iso = core.open_iso(self.iso_path, self.runner)
            root = core.root_disk(self.runner)
            self.devices = []
            for d in core.list_devices(self.runner):
                try:
                    core.validate_target(d, iso.size, root, test_mode=TEST_MODE)
                except core.UsbError:
                    continue
                self.devices.append(d)
        except core.UsbError as e:
            self._error_label(str(e))
            self._buttons(back=True, forward=None)
            return

        if not self.devices:
            self._error_label("No writable disks found (all are mounted or back /).")
            self._buttons(back=True, forward=None)
            return

        combo = Gtk.ComboBoxText()
        for d in self.devices:
            combo.append_text(d.describe())
        combo.set_active(0)
        self.target = self.devices[0].path
        combo.connect("changed", lambda c: self._set_device(c.get_active()))
        self.box.pack_start(combo, False, False, 0)
        self._buttons(back=True, forward=("Continue", "options"))

    def _set_device(self, idx: int) -> None:
        if 0 <= idx < len(self.devices):
            self.target = self.devices[idx].path

    def _step_options(self) -> None:
        self._title("Options", f"Target {self.target}")
        p = self._current_device()

        persist_sw = Gtk.Switch()
        persist_sw.set_active(self.persist)
        persist_sw.connect("notify::active", lambda s, _: setattr(self, "persist", s.get_active()))
        self._row("Add the hyprtk-persist partition", persist_sw)

        size_combo = Gtk.ComboBoxText()
        for s in SIZE_CHOICES:
            size_combo.append_text(s)
        size_combo.set_active(SIZE_CHOICES.index(self.size) if self.size in SIZE_CHOICES else 0)
        size_combo.connect("changed", lambda c: setattr(self, "size", c.get_active_text() or "rest"))
        self._row("Persistence size", size_combo)

        if p is not None and p.persist_partition() is not None:
            refresh_sw = Gtk.Switch()
            refresh_sw.set_active(self.refresh)
            refresh_sw.connect("notify::active", lambda s, _: setattr(self, "refresh", s.get_active()))
            self._row("Keep the existing partition", refresh_sw)
            note = Gtk.Label(label="An existing hyprtk-persist partition was found.", xalign=0)
            note.get_style_context().add_class("dim")
            self.box.pack_start(note, False, False, 0)

        self._buttons(back=True, forward=("Review", "review"))

    def _current_device(self) -> core.Device | None:
        for d in self.devices:
            if d.path == self.target:
                return d
        return None

    def _step_review(self) -> None:
        self._title("Review", "This permanently erases the target disk.")
        try:
            iso = core.open_iso(self.iso_path, self.runner)
            dev = self._current_device() or core.find_device(self.runner, self.target)
            plan = core.build_plan(
                iso, dev,
                core.Options(persist=self.persist, size=self.size, refresh=self.refresh, test_mode=TEST_MODE),
            )
        except core.UsbError as e:
            self._error_label(str(e))
            self._buttons(back=True, forward=None)
            return

        mode = {
            core.MODE_NONE: "none",
            core.MODE_REFRESH: f"{plan.partition_dev} (kept)",
            core.MODE_FRESH: f"{plan.partition_dev}  label {core.PERSIST_LABEL}",
        }[plan.mode]
        lines = [
            f"ISO      {iso.path} ({human_bytes(iso.size)})",
            f"Label    {iso.label or '?'}",
            f"Target   {dev.describe()}",
            f"Size     {human_bytes(dev.size)}",
            f"Persist  {mode}",
        ]
        if plan.mode in (core.MODE_FRESH, core.MODE_REFRESH):
            lines.append(
                f"Region   sectors {plan.start_sectors}..{plan.start_sectors + plan.size_sectors - 1} "
                f"({human_bytes(plan.size_sectors * 512)})"
            )
        for line in lines:
            lbl = Gtk.Label(label=line, xalign=0)
            self.box.pack_start(lbl, False, False, 0)
        for w in plan.warnings:
            wl = Gtk.Label(label="! " + w, xalign=0)
            wl.get_style_context().add_class("warn")
            self.box.pack_start(wl, False, False, 0)

        erase = Gtk.Label(label=f"This ERASES {dev.path}.", xalign=0)
        erase.get_style_context().add_class("err")
        self.box.pack_start(erase, False, False, 0)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.END)
        back = Gtk.Button(label="Back")
        back.connect("clicked", lambda *_: self.go_back())
        row.pack_end(back, False, False, 0)
        write = Gtk.Button(label="Write")
        write.get_style_context().add_class("suggested-action")
        write.connect("clicked", lambda *_: self._start_write())
        row.pack_end(write, False, False, 0)
        self.box.pack_end(row, False, False, 0)

    def _step_progress(self) -> None:
        self._title("Writing", "Do not unplug the device.")
        self.bar = Gtk.ProgressBar()
        self.bar.set_show_text(True)
        self.box.pack_start(self.bar, False, False, 0)
        self.status = Gtk.Label(label="starting…", xalign=0)
        self.status.get_style_context().add_class("dim")
        self.box.pack_start(self.status, False, False, 0)

    def _step_done(self) -> None:
        self._title("Done")
        msg = 'Boot the stick and pick "Hyprtk live with persistence".'
        lbl = Gtk.Label(label=msg, xalign=0)
        lbl.get_style_context().add_class("ok")
        lbl.set_line_wrap(True)
        self.box.pack_start(lbl, False, False, 0)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.END)
        close = Gtk.Button(label="Close")
        close.connect("clicked", lambda *_: self.destroy())
        row.pack_end(close, False, False, 0)
        self.box.pack_end(row, False, False, 0)

    def _step_error(self) -> None:
        self._title("Failed")
        self._error_label(self._error or "unknown error")
        self._buttons(back=True, forward=None)

    def _error_label(self, msg: str) -> None:
        lbl = Gtk.Label(label=msg, xalign=0)
        lbl.get_style_context().add_class("err")
        lbl.set_line_wrap(True)
        self.box.pack_start(lbl, False, False, 0)

    def _row(self, label: str, widget: Gtk.Widget) -> None:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        lbl = Gtk.Label(label=label, xalign=0)
        lbl.set_hexpand(True)
        row.pack_start(lbl, True, True, 0)
        row.pack_end(widget, False, False, 0)
        self.box.pack_start(row, False, False, 0)

    # ── writing ────────────────────────────────────────────────────────
    def _start_write(self) -> None:
        try:
            cmd = _elevate(_helper_command()) + [
                "--iso", self.iso_path,
                "--target", self.target,
                "--size", self.size,
            ]
        except core.UsbError as e:
            self._error = str(e)
            self.advance("error")
            return
        if not self.persist:
            cmd.append("--no-persist")
        if self.refresh:
            cmd.append("--refresh")
        if TEST_MODE:
            cmd.append("--test")

        self._error = None
        self.step = "progress"
        self.show_step()
        threading.Thread(target=self._run_write, args=(cmd,), daemon=True).start()

    def _run_write(self, cmd: list[str]) -> None:
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        except OSError as e:
            GLib.idle_add(self._fail, str(e))
            return
        assert proc.stdout is not None
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            try:
                msg = json.loads(line)
            except ValueError:
                continue
            GLib.idle_add(self._progress, msg)
        err = (proc.stderr.read() if proc.stderr else "").strip()
        rc = proc.wait()
        if rc != 0:
            GLib.idle_add(self._fail, err or f"write failed (exit {rc})")
        else:
            GLib.idle_add(self._finish)

    def _progress(self, msg: dict) -> bool:
        stage = msg.get("stage", "")
        if stage == "copy":
            total = msg.get("total") or 0
            written = msg.get("written") or 0
            if total:
                self.bar.set_fraction(min(written / total, 1.0))
                self.bar.set_text(f"copying {human_bytes(written)} / {human_bytes(total)}")
        elif stage == "partition":
            self.status.set_text("adding the persistence partition…")
        elif stage == "format":
            self.status.set_text(f"formatting {core.PERSIST_LABEL}…")
        return False

    def _fail(self, msg: str) -> bool:
        self._error = msg
        self.advance("error")
        return False

    def _finish(self) -> bool:
        self.advance("done")
        return False


class App(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="org.hyprtk.usb", flags=0)

    def do_activate(self) -> None:
        win = self.get_active_window() or Window(self)
        win.show_all()


def main(argv: list[str] | None = None) -> int:
    app = App()
    return app.run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    sys.exit(main())
