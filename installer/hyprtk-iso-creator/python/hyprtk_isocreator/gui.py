"""GTK 4 front end for the Hyprtk ISO builder.

The GUI runs unprivileged and collects the builder's options across a short
wizard. The single privileged operation — running ``hyprtk-iso-builder.sh``
(which needs root for ``mkarchiso``) — is performed by
``hyprtk_isocreator.helper`` launched through ``pkexec``, so the GTK app never
runs as root. The builder's live output is shown in a scrolling log.
"""

from __future__ import annotations

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")

import json  # noqa: E402
import os  # noqa: E402
import pwd  # noqa: E402
import shutil  # noqa: E402
import subprocess  # noqa: E402
import sys  # noqa: E402
import threading  # noqa: E402

from gi.repository import Gdk, GLib, Gtk  # noqa: E402

from . import __version__, core, paths  # noqa: E402
from .ui import load_palette  # noqa: E402

TEST_MODE = os.environ.get("HYPRTK_ISO_TEST") == "1"


def _current_user() -> str:
    try:
        return pwd.getpwuid(os.getuid()).pw_name
    except (KeyError, OSError):
        return os.environ.get("USER") or ""


def _in_place_helper() -> list[str]:
    # Run in place: hand the package's parent to PYTHONPATH so it imports as
    # root too (the user's site-packages isn't on root's sys.path).
    parent = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    envbin = shutil.which("env") or "/usr/bin/env"
    py = sys.executable or "python3"
    return [envbin, f"PYTHONPATH={parent}", py, "-m", "hyprtk_isocreator.helper"]


def _helper_command() -> list[str]:
    exe = shutil.which("hyprtk-iso-creator-helper")
    return [exe] if exe else _in_place_helper()


def _elevate(cmd: list[str]) -> list[str]:
    if os.geteuid() == 0 or TEST_MODE:
        return cmd
    pkexec = shutil.which("pkexec")
    if not pkexec:
        raise core.BuildError("pkexec not found - run the app as root or install polkit")
    return [pkexec, *cmd]


class Window(Gtk.ApplicationWindow):
    def __init__(self, app: Gtk.Application) -> None:
        super().__init__(application=app, title="Hyprtk ISO Creator")
        self.set_default_size(780, 640)
        self.p = load_palette()

        self.step = "source"
        self.opts = core.Options(iso_label=core.default_label())
        self._error: str | None = None
        self._result: dict = {}
        self._stage = ""

        # Match hyprtk-bar's floating dialogs: no client-side decorations (the
        # compositor draws the pywal border + rounding); the panel is frosted at
        # the bar's opacity. GTK4 surfaces are RGBA by default.
        self.set_decorated(False)
        self.set_resizable(False)
        self.add_css_class("hyprtk-isocreator")
        settings = Gtk.Settings.get_default()
        if settings is not None:
            settings.set_property("gtk-application-prefer-dark-theme", True)
        self._apply_css()

        self.panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=0)
        self.panel.add_css_class("panel")
        self.set_child(self.panel)
        self.panel.append(self._header_row())
        self.box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        self.box.set_margin_top(16)
        self.box.set_margin_bottom(16)
        self.box.set_margin_start(16)
        self.box.set_margin_end(16)
        self.box.set_vexpand(True)
        self.panel.append(self.box)
        self.show_step()

    # ── header ─────────────────────────────────────────────────────────
    def _header_row(self) -> Gtk.Widget:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add_css_class("header")
        title = Gtk.Label(label="Hyprtk ISO Creator", xalign=0)
        title.add_css_class("title")
        title.set_hexpand(True)
        row.append(title)
        if self.p.theme_name:
            theme_lbl = Gtk.Label(label=self.p.theme_name, xalign=1)
            theme_lbl.add_css_class("dim")
            row.append(theme_lbl)

        close = Gtk.Button(label="\u00d7")
        close.add_css_class("close")
        close.set_has_frame(False)
        close.set_focusable(False)
        close.connect("clicked", lambda *_: self.close())
        row.append(close)

        handle = Gtk.WindowHandle()
        handle.set_child(row)
        return handle

    # ── theming ────────────────────────────────────────────────────────
    def _apply_css(self) -> None:
        p = self.p
        css = f"""
@define-color bg {p.bg};
@define-color fg {p.fg};
@define-color dim {p.dim};
@define-color accent {p.accent};
@define-color accent_alt {p.accent2};
@define-color err {p.err};
@define-color warn {p.warn};

.hyprtk-isocreator {{ background-color: transparent; color: @fg; border: none; }}
.hyprtk-isocreator .panel {{ background-color: alpha(@bg, {p.opacity:.3f}); }}

.hyprtk-isocreator .header {{ padding: 10px 10px 2px 16px; }}
.hyprtk-isocreator button.close {{
    background-image: none; background-color: transparent;
    border: none; box-shadow: none;
    color: @dim; font-size: 15pt; padding: 0 8px; min-height: 0;
}}
.hyprtk-isocreator button.close:hover {{ color: @err; }}

.hyprtk-isocreator label {{ color: @fg; }}
.hyprtk-isocreator label.title {{ color: @accent; font-weight: bold; font-size: 15pt; }}
.hyprtk-isocreator label.dim {{ color: @dim; }}
.hyprtk-isocreator label.warn {{ color: @warn; }}
.hyprtk-isocreator label.err {{ color: @err; }}
.hyprtk-isocreator label.ok {{ color: @accent_alt; }}
.hyprtk-isocreator label.mono {{ font-family: monospace; }}

/* The GTK theme paints a background-image/shadow over any background-color, so
   reset them (the bar does the same inside its menu). */
.hyprtk-isocreator button {{
    background-image: none; box-shadow: none; text-shadow: none;
    background-color: alpha(@accent_alt, 0.10);
    color: @fg;
    border: 1px solid alpha(@accent_alt, 0.25);
    border-radius: 10px;
    padding: 6px 14px;
}}
.hyprtk-isocreator button:hover {{ background-color: alpha(@accent_alt, 0.18); }}
.hyprtk-isocreator button.suggested-action {{
    background-color: alpha(@accent, 0.85);
    color: #ffffff;
    border: 1px solid alpha(@accent, 0.95);
    font-weight: bold;
}}
.hyprtk-isocreator button.suggested-action:hover {{ background-color: @accent; }}

.hyprtk-isocreator entry {{
    background-image: none; box-shadow: none;
    background-color: alpha(@accent_alt, 0.08);
    color: @fg;
    border: 1px solid alpha(@accent_alt, 0.25);
    border-radius: 10px;
    padding: 5px 10px;
}}

/* Switches: reset the theme's background-image/shadow (else a light square
   shows around the switch). */
.hyprtk-isocreator switch {{
    background-image: none; box-shadow: none;
    background-color: alpha(@accent_alt, 0.20);
    border: 1px solid alpha(@accent_alt, 0.30);
    border-radius: 12px;
    min-width: 40px; min-height: 22px;
}}
.hyprtk-isocreator switch:checked {{
    background-image: none; box-shadow: none;
    background-color: @accent;
    border-color: @accent;
}}
.hyprtk-isocreator switch slider {{
    background-image: none; box-shadow: none;
    background-color: #ffffff;
    border: none;
    border-radius: 8px;
    min-width: 16px; min-height: 16px;
    margin: 2px;
}}

.hyprtk-isocreator progressbar trough {{
    background-color: alpha(@accent_alt, 0.12);
    border-radius: 8px;
    min-height: 10px;
}}
.hyprtk-isocreator progressbar progress {{ background-color: @accent; border-radius: 8px; }}

.hyprtk-isocreator scrolledwindow {{
    border: 1px solid alpha(@accent_alt, 0.25);
    border-radius: 10px;
    background-color: alpha(@accent_alt, 0.05);
}}
.hyprtk-isocreator textview, .hyprtk-isocreator textview text {{
    background-color: transparent;
    color: @fg;
    font-family: monospace;
    font-size: 9pt;
}}
"""
        provider = Gtk.CssProvider()
        provider.load_from_data(css.encode())
        display = self.get_display() or Gdk.Display.get_default()
        if display is not None:
            Gtk.StyleContext.add_provider_for_display(
                display, provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            )

    # ── widgets ────────────────────────────────────────────────────────
    def _clear(self) -> None:
        child = self.box.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            self.box.remove(child)
            child = nxt

    def _title(self, text: str, sub: str = "") -> None:
        lbl = Gtk.Label(label=text, xalign=0)
        lbl.add_css_class("title")
        self.box.append(lbl)
        if sub:
            s = Gtk.Label(label=sub, xalign=0)
            s.add_css_class("dim")
            s.set_wrap(True)
            self.box.append(s)

    def _buttons(self, back: bool, forward: tuple[str, str] | None) -> None:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.END)
        row.set_margin_top(6)
        if forward:
            label, nxt = forward
            b = Gtk.Button(label=label)
            b.add_css_class("suggested-action")
            b.connect("clicked", lambda *_: self.advance(nxt))
            row.append(b)
        if back:
            b = Gtk.Button(label="Back")
            b.connect("clicked", lambda *_: self.go_back())
            row.append(b)
        self.box.append(row)

    def _row(self, label: str, widget: Gtk.Widget) -> None:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        lbl = Gtk.Label(label=label, xalign=0)
        lbl.set_hexpand(True)
        row.append(lbl)
        row.append(widget)
        self.box.append(row)

    def _entry_row(self, label: str, value: str, placeholder: str, key: str,
                   folder: bool = False) -> None:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        lbl = Gtk.Label(label=label, xalign=0)
        lbl.set_size_request(150, -1)
        row.append(lbl)
        entry = Gtk.Entry()
        entry.set_text(value)
        entry.set_placeholder_text(placeholder)
        entry.set_hexpand(True)
        entry.connect("changed", lambda e: setattr(self.opts, key, e.get_text()))
        row.append(entry)
        if folder:
            browse = Gtk.Button(label="Choose…")
            browse.connect("clicked", lambda *_: self._choose_dir(
                lambda path: (entry.set_text(path), setattr(self.opts, key, path))))
            row.append(browse)
        self.box.append(row)

    def _switch_row(self, label: str, active: bool, key: str) -> None:
        sw = Gtk.Switch()
        sw.set_active(active)
        sw.connect("notify::active", lambda s, _: setattr(self.opts, key, s.get_active()))
        self._row(label, sw)

    def _choose_dir(self, on_pick) -> None:
        dlg = Gtk.FileChooserDialog(
            title="Select a folder", transient_for=self,
            action=Gtk.FileChooserAction.SELECT_FOLDER,
        )
        dlg.add_buttons("Cancel", Gtk.ResponseType.CANCEL, "Select", Gtk.ResponseType.OK)
        dlg.connect("response", lambda d, r: (
            on_pick(d.get_file().get_path()) if r == Gtk.ResponseType.OK
            and d.get_file() is not None else None,
            d.destroy(),
        ))
        dlg.present()

    # ── steps ──────────────────────────────────────────────────────────
    def show_step(self) -> None:
        self._clear()
        getattr(self, f"_step_{self.step}")()

    def go_back(self) -> None:
        self.step = {
            "output": "source", "options": "output", "review": "options",
            "error": "review",
        }.get(self.step, "source")
        self.show_step()

    def advance(self, nxt: str) -> None:
        self.step = nxt
        self.show_step()

    def _step_source(self) -> None:
        self._title(
            "Choose the hyprtk source",
            "The dotfiles tree vendored into /etc/skel. Leave blank to use "
            "~/hyprtk, or clone hyprtk/dotfiles when it is absent.",
        )
        self._entry_row("Dotfiles source", self.opts.hyprtk_dir,
                        "Auto (~/hyprtk, else clone)", "hyprtk_dir", folder=True)
        if os.path.isdir(os.path.expanduser("~/hyprtk")):
            hint = Gtk.Label(label="Found ~/hyprtk.", xalign=0)
            hint.add_css_class("ok")
            self.box.append(hint)
        self._buttons(back=False, forward=("Continue", "output"))

    def _step_output(self) -> None:
        self._title("Output", "What the builder writes, and where it stages the work.")
        self._entry_row("ISO name", self.opts.iso_name, "hyprtk", "iso_name")
        self._entry_row("ISO label", self.opts.iso_label,
                        f"default {core.default_label()}", "iso_label")
        self._entry_row("Output directory", self.opts.out_dir,
                        "Default (your home)", "out_dir", folder=True)
        self._entry_row("Build root", self.opts.build_root,
                        "Default (/tmp/hyprtk-iso-build)", "build_root", folder=True)
        self._buttons(back=True, forward=("Continue", "options"))

    def _step_options(self) -> None:
        self._title("Options", "Best-effort extras can be skipped for a faster, "
                               "reproducible build.")
        self._switch_row("Build the AUR extras", self.opts.aur, "aur")
        self._switch_row("Build matuwall from source", self.opts.matuwall, "matuwall")
        self._switch_row("Assemble the profile only (no ISO)", self.opts.profile_only,
                         "profile_only")
        self._switch_row("Keep the build work directory", self.opts.keep_work, "keep_work")
        self._buttons(back=True, forward=("Review", "review"))

    def _step_review(self) -> None:
        self._title("Review", "Building needs root, network access and ~20 GB free in /tmp.")
        o = self.opts
        rows = [
            ("Source", o.hyprtk_dir or "Auto (~/hyprtk, else clone)"),
            ("ISO name", o.iso_name or "hyprtk"),
            ("ISO label", o.iso_label or f"default {core.default_label()}"),
            ("Output", o.out_dir or "Default (your home)"),
            ("Build root", o.build_root or "Default (/tmp/hyprtk-iso-build)"),
            ("AUR extras", "yes" if o.aur else "no"),
            ("matuwall", "yes" if o.matuwall else "no"),
            ("Mode", "Profile only (no ISO)" if o.profile_only else "Full ISO"),
            ("Keep work dir", "yes" if o.keep_work else "no"),
        ]
        for label, value in rows:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
            key = Gtk.Label(label=label, xalign=0)
            key.add_css_class("dim")
            key.set_size_request(150, -1)
            val = Gtk.Label(label=value, xalign=0)
            val.set_wrap(True)
            row.append(key)
            row.append(val)
            self.box.append(row)

        for err in core.validate(o):
            el = Gtk.Label(label=err, xalign=0)
            el.add_css_class("err")
            el.set_wrap(True)
            self.box.append(el)

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.END)
        build = Gtk.Button(label="Build")
        build.add_css_class("suggested-action")
        build.connect("clicked", lambda *_: self._start_build())
        row.append(build)
        back = Gtk.Button(label="Back")
        back.connect("clicked", lambda *_: self.go_back())
        row.append(back)
        self.box.append(row)

    def _step_progress(self) -> None:
        self._title("Building", "This can take a long time - do not close the window.")
        self.stage_lbl = Gtk.Label(label="starting\u2026", xalign=0)
        self.stage_lbl.add_css_class("dim")
        self.box.append(self.stage_lbl)
        self.bar = Gtk.ProgressBar()
        self.bar.set_show_text(True)
        self.box.append(self.bar)

        self.buf = Gtk.TextBuffer()
        self._make_tags(self.buf)
        self.view = Gtk.TextView(buffer=self.buf)
        self.view.set_editable(False)
        self.view.set_monospace(True)
        self.view.set_wrap_mode(Gtk.WrapMode.WORD_CHAR)
        self.scroll = Gtk.ScrolledWindow()
        self.scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC)
        self.scroll.set_child(self.view)
        self.scroll.set_vexpand(True)
        self.box.append(self.scroll)

    def _make_tags(self, buf: Gtk.TextBuffer) -> None:
        p = self.p
        for name, color in (
            ("text", p.fg), ("dim", p.dim), ("info", p.accent),
            ("ok", p.accent2), ("warn", p.warn), ("err", p.err),
            ("title", p.accent),
        ):
            buf.create_tag(name, foreground=color)

    def _step_done(self) -> None:
        profile_only = self.opts.profile_only
        self._title("Profile ready" if profile_only else "ISO built")
        msg = ""
        if profile_only and self._result.get("profile"):
            msg = f"Profile: {self._result['profile']}"
        elif self._result.get("iso"):
            msg = f"ISO: {self._result['iso']}"
            if self._result.get("size"):
                msg += f"  ({self._result['size']})"
        lbl = Gtk.Label(label=msg or "Build completed.", xalign=0)
        lbl.add_css_class("ok")
        lbl.add_css_class("mono")
        lbl.set_wrap(True)
        self.box.append(lbl)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_halign(Gtk.Align.END)
        close = Gtk.Button(label="Close")
        close.connect("clicked", lambda *_: self.close())
        row.append(close)
        self.box.append(row)

    def _step_error(self) -> None:
        self._title("Failed")
        lbl = Gtk.Label(label=self._error or "unknown error", xalign=0)
        lbl.add_css_class("err")
        lbl.set_wrap(True)
        self.box.append(lbl)
        self._buttons(back=True, forward=None)

    # ── building ───────────────────────────────────────────────────────
    def _start_build(self) -> None:
        errs = core.validate(self.opts)
        if errs:
            self._error = "\n".join(errs)
            self.advance("error")
            return
        try:
            builder = str(paths.builder_path())
        except FileNotFoundError as e:
            self._error = str(e)
            self.advance("error")
            return
        try:
            cmd = _elevate(_helper_command()) + [
                "--builder", builder, "--user", _current_user(),
                *core.builder_args(self.opts),
            ]
        except core.BuildError as e:
            self._error = str(e)
            self.advance("error")
            return

        self._error = None
        self._result = {}
        self.step = "progress"
        self.show_step()
        threading.Thread(target=self._run_build, args=(cmd,), daemon=True).start()

    def _run_build(self, cmd: list[str]) -> None:
        try:
            proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                    stderr=subprocess.PIPE, text=True)
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
            GLib.idle_add(self._dispatch, msg)
        err = (proc.stderr.read() if proc.stderr else "").strip()
        rc = proc.wait()
        if rc != 0:
            GLib.idle_add(self._fail, err or f"build failed (exit {rc})")

    # ── helper messages ────────────────────────────────────────────────
    def _dispatch(self, msg: dict) -> bool:
        kind = msg.get("type")
        if kind == "log":
            self._append(msg.get("level") or "text", msg.get("text") or "")
        elif kind == "stage":
            self._stage = msg.get("name") or ""
            self.stage_lbl.set_text(msg.get("label") or self._stage)
            self.bar.set_fraction(core.stage_fraction(self._stage))
            if self._stage == "iso":
                self.bar.set_text("building ISO\u2026")
            else:
                self.bar.set_text("")
        elif kind == "done":
            self._result = msg
            self.advance("done")
        elif kind == "error":
            self._fail(msg.get("message") or "build failed")
        return False

    def _append(self, level: str, text: str) -> bool:
        end = self.buf.get_end_iter()
        self.buf.insert_with_tags_by_name(end, text + "\n",
                                          level if level else "text")
        adj = self.scroll.get_vadjustment()
        adj.set_value(adj.get_upper())
        return False

    def _fail(self, msg: str) -> bool:
        self._error = msg
        self.advance("error")
        return False


class App(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(application_id="org.hyprtk.isocreator", flags=0)

    def do_activate(self) -> None:
        win = self.get_active_window() or Window(self)
        win.present()


def main(argv: list[str] | None = None) -> int:
    app = App()
    return app.run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    sys.exit(main())
