"""Qt (PySide6) front end for the Hyprtk ISO builder.

The GUI runs unprivileged and collects the builder's options across a short
wizard. The single privileged operation — running ``hyprtk-iso-builder.sh``
(which needs root for ``mkarchiso``) — is performed by
``hyprtk_isocreator.helper`` launched through ``pkexec``, so the Qt app never
runs as root. The builder's live output is shown in a scrolling log.

This is the Qt replacement for the former GTK 4 front end: a frameless,
non-resizable wizard themed from the running hyprtk-bar palette
(``ui.load_palette``). The compositor draws the pywal border + rounding.
"""

from __future__ import annotations

import json
import os
import pwd
import shutil
import subprocess
import sys
import threading
from html import escape

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor, QPainter, QTextCursor
from PySide6.QtWidgets import (
    QAbstractButton,
    QApplication,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QProgressBar,
    QPushButton,
    QSizePolicy,
    QTextEdit,
    QVBoxLayout,
    QWidget,
)

from . import core, paths
from .ui import Palette, load_palette

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


def _rgba(hex_color: str, alpha: float) -> str:
    c = QColor(hex_color)
    if not c.isValid():
        c = QColor("#000000")
    return f"rgba({c.red()},{c.green()},{c.blue()},{int(round(alpha * 255))})"


def build_qss(p: Palette) -> str:
    """The hyprtk ISO Creator stylesheet (pywal-driven frosted panel, mauve
    accents, cyan tints). Mirrors the old GTK CSS."""
    return f"""
QLabel {{ color: {p.fg}; }}
QLabel[role="title"] {{ color: {p.accent}; font-weight: bold; font-size: 15pt; }}
QLabel[role="dim"] {{ color: {p.dim}; }}
QLabel[role="warn"] {{ color: {p.warn}; }}
QLabel[role="err"] {{ color: {p.err}; }}
QLabel[role="ok"] {{ color: {p.accent2}; }}

QFrame#panel {{ background-color: {_rgba(p.bg, p.opacity)}; border-radius: 12px; }}
QWidget#header {{ background: transparent; }}

QPushButton {{
    background-color: {_rgba(p.accent2, 0.10)};
    color: {p.fg};
    border: 1px solid {_rgba(p.accent2, 0.25)};
    border-radius: 10px;
    padding: 6px 14px;
}}
QPushButton:hover {{ background-color: {_rgba(p.accent2, 0.18)}; }}
QPushButton[role="primary"] {{
    background-color: {_rgba(p.accent, 0.85)};
    color: #ffffff;
    border: 1px solid {_rgba(p.accent, 0.95)};
    font-weight: bold;
}}
QPushButton[role="primary"]:hover {{ background-color: {p.accent}; }}
QPushButton#close {{
    background: transparent; border: none;
    color: {p.dim}; font-size: 15pt; padding: 0 8px;
}}
QPushButton#close:hover {{ color: {p.err}; }}

QLineEdit {{
    background-color: {_rgba(p.accent2, 0.08)};
    color: {p.fg};
    border: 1px solid {_rgba(p.accent2, 0.25)};
    border-radius: 10px;
    padding: 5px 10px;
}}
QLineEdit:focus {{ border: 1px solid {_rgba(p.accent, 0.65)}; }}

QProgressBar {{
    background-color: {_rgba(p.accent2, 0.12)};
    border: none; border-radius: 8px;
    min-height: 10px; max-height: 10px;
    text-align: center; color: {p.fg};
}}
QProgressBar::chunk {{ background-color: {p.accent}; border-radius: 8px; }}

QTextEdit#log {{
    background-color: {_rgba(p.accent2, 0.05)};
    color: {p.fg};
    border: 1px solid {_rgba(p.accent2, 0.25)};
    border-radius: 10px;
    font-family: monospace;
    font-size: 9pt;
}}
"""


class Switch(QAbstractButton):
    """A compact pill toggle matching the old ``Gtk.Switch`` look."""

    def __init__(self, checked: bool = False, on_color: str = "#c084fc",
                 off_color: str = "#22d3ee") -> None:
        super().__init__()
        self.setCheckable(True)
        self.setChecked(checked)
        self.setCursor(Qt.PointingHandCursor)
        self.setFixedSize(46, 24)
        self._on = QColor(on_color)
        self._off = QColor(off_color)
        self._off.setAlphaF(0.35)

    def paintEvent(self, _event) -> None:  # noqa: N802 (Qt override)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing, True)
        rect = self.rect().adjusted(1, 1, -1, -1)
        radius = rect.height() / 2.0
        painter.setPen(Qt.NoPen)
        painter.setBrush(self._on if self.isChecked() else self._off)
        painter.drawRoundedRect(rect, radius, radius)
        d = rect.height() - 4
        y = rect.top() + 2
        x = (rect.right() - d - 2) if self.isChecked() else (rect.left() + 2)
        painter.setBrush(QColor("#ffffff"))
        painter.drawEllipse(x, y, d, d)


class DragBar(QWidget):
    """Header strip that moves the frameless toplevel (Wayland-safe)."""

    def mousePressEvent(self, event) -> None:  # noqa: N802 (Qt override)
        if event.button() == Qt.LeftButton:
            handle = self.window().windowHandle()
            if handle is not None:
                handle.startSystemMove()
                event.accept()
                return
        super().mousePressEvent(event)


class Window(QWidget):
    log_msg = Signal(str, str)
    stage_msg = Signal(dict)
    done_msg = Signal(dict)
    failed = Signal(str)

    def __init__(self) -> None:
        super().__init__()
        self.setObjectName("root")
        self.setWindowTitle("Hyprtk ISO Creator")
        self.setWindowFlag(Qt.FramelessWindowHint, True)
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setFixedSize(780, 640)
        self.p = load_palette()

        self.step = "source"
        self.opts = core.Options(iso_label=core.default_label())
        self._error: str | None = None
        self._result: dict = {}
        self._stage = ""

        app = QApplication.instance()
        if app is not None:
            app.setStyleSheet(build_qss(self.p))

        panel = QFrame()
        panel.setObjectName("panel")
        outer = QVBoxLayout(self)
        outer.setContentsMargins(0, 0, 0, 0)
        outer.addWidget(panel)

        pl = QVBoxLayout(panel)
        pl.setContentsMargins(0, 0, 0, 0)
        pl.setSpacing(0)
        pl.addWidget(self._header_row())

        body = QWidget()
        self.body_layout = QVBoxLayout(body)
        self.body_layout.setContentsMargins(16, 16, 16, 16)
        self.body_layout.setSpacing(12)
        pl.addWidget(body, 1)

        self.log_msg.connect(self._append)
        self.stage_msg.connect(self._on_stage)
        self.done_msg.connect(self._on_done)
        self.failed.connect(self._fail)
        self.show_step()

    # ── header ─────────────────────────────────────────────────────────
    def _header_row(self) -> QWidget:
        bar = DragBar()
        bar.setObjectName("header")
        row = QHBoxLayout(bar)
        row.setContentsMargins(16, 10, 10, 2)
        row.setSpacing(8)
        title = QLabel("Hyprtk ISO Creator")
        title.setProperty("role", "title")
        title.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        row.addWidget(title)
        if self.p.theme_name:
            theme_lbl = QLabel(self.p.theme_name)
            theme_lbl.setProperty("role", "dim")
            row.addWidget(theme_lbl)
        close = QPushButton("\u00d7")
        close.setObjectName("close")
        close.setFocusPolicy(Qt.NoFocus)
        close.setCursor(Qt.PointingHandCursor)
        close.clicked.connect(self.close)
        row.addWidget(close)
        return bar

    # ── widgets ────────────────────────────────────────────────────────
    def _clear(self) -> None:
        while self.body_layout.count():
            item = self.body_layout.takeAt(0)
            widget = item.widget()
            if widget is not None:
                widget.deleteLater()

    def _title(self, text: str, sub: str = "") -> None:
        lbl = QLabel(text)
        lbl.setProperty("role", "title")
        self.body_layout.addWidget(lbl)
        if sub:
            s = QLabel(sub)
            s.setProperty("role", "dim")
            s.setWordWrap(True)
            self.body_layout.addWidget(s)

    def _buttons(self, back: bool, forward: tuple[str, str] | None) -> None:
        row = QWidget()
        h = QHBoxLayout(row)
        h.setContentsMargins(0, 6, 0, 0)
        h.setSpacing(8)
        h.addStretch(1)
        if forward:
            label, nxt = forward
            b = QPushButton(label)
            b.setProperty("role", "primary")
            b.setCursor(Qt.PointingHandCursor)
            b.clicked.connect(lambda *_, n=nxt: self.advance(n))
            h.addWidget(b)
        if back:
            b = QPushButton("Back")
            b.setCursor(Qt.PointingHandCursor)
            b.clicked.connect(self.go_back)
            h.addWidget(b)
        self.body_layout.addWidget(row)

    def _row(self, label: str, widget: QWidget) -> None:
        row = QWidget()
        h = QHBoxLayout(row)
        h.setContentsMargins(0, 0, 0, 0)
        h.setSpacing(12)
        lbl = QLabel(label)
        lbl.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        h.addWidget(lbl)
        h.addWidget(widget)
        self.body_layout.addWidget(row)

    def _entry_row(self, label: str, value: str, placeholder: str, key: str,
                   folder: bool = False) -> None:
        row = QWidget()
        h = QHBoxLayout(row)
        h.setContentsMargins(0, 0, 0, 0)
        h.setSpacing(8)
        lbl = QLabel(label)
        lbl.setFixedWidth(150)
        h.addWidget(lbl)
        entry = QLineEdit(value)
        entry.setPlaceholderText(placeholder)
        entry.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Preferred)
        entry.textChanged.connect(lambda t, k=key: setattr(self.opts, k, t))
        h.addWidget(entry)
        if folder:
            browse = QPushButton("Choose\u2026")
            browse.setCursor(Qt.PointingHandCursor)
            browse.clicked.connect(lambda *_, e=entry, k=key: self._choose_dir(e, k))
            h.addWidget(browse)
        self.body_layout.addWidget(row)

    def _switch_row(self, label: str, active: bool, key: str) -> None:
        sw = Switch(active, self.p.accent, self.p.accent2)
        sw.toggled.connect(lambda v, k=key: setattr(self.opts, k, v))
        self._row(label, sw)

    def _choose_dir(self, entry: QLineEdit, key: str) -> None:
        path = QFileDialog.getExistingDirectory(self, "Select a folder", os.path.expanduser("~"))
        if path:
            entry.setText(path)
            setattr(self.opts, key, path)

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
            hint = QLabel("Found ~/hyprtk.")
            hint.setProperty("role", "ok")
            self.body_layout.addWidget(hint)
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
            row = QWidget()
            h = QHBoxLayout(row)
            h.setContentsMargins(0, 0, 0, 0)
            h.setSpacing(12)
            key = QLabel(label)
            key.setProperty("role", "dim")
            key.setFixedWidth(150)
            val = QLabel(value)
            val.setWordWrap(True)
            h.addWidget(key)
            h.addWidget(val, 1)
            self.body_layout.addWidget(row)

        for err in core.validate(o):
            el = QLabel(err)
            el.setProperty("role", "err")
            el.setWordWrap(True)
            self.body_layout.addWidget(el)

        row = QWidget()
        h = QHBoxLayout(row)
        h.setContentsMargins(0, 0, 0, 0)
        h.setSpacing(8)
        h.addStretch(1)
        build = QPushButton("Build")
        build.setProperty("role", "primary")
        build.setCursor(Qt.PointingHandCursor)
        build.clicked.connect(self._start_build)
        h.addWidget(build)
        back = QPushButton("Back")
        back.setCursor(Qt.PointingHandCursor)
        back.clicked.connect(self.go_back)
        h.addWidget(back)
        self.body_layout.addWidget(row)

    def _step_progress(self) -> None:
        self._title("Building", "This can take a long time - do not close the window.")
        self.stage_lbl = QLabel("starting\u2026")
        self.stage_lbl.setProperty("role", "dim")
        self.body_layout.addWidget(self.stage_lbl)
        self.bar = QProgressBar()
        self.bar.setRange(0, 100)
        self.bar.setTextVisible(True)
        self.body_layout.addWidget(self.bar)
        self.log = QTextEdit()
        self.log.setObjectName("log")
        self.log.setReadOnly(True)
        self.log.setLineWrapMode(QTextEdit.WidgetWidth)
        self.body_layout.addWidget(self.log, 1)

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
        lbl = QLabel(msg or "Build completed.")
        lbl.setProperty("role", "ok")
        lbl.setWordWrap(True)
        self.body_layout.addWidget(lbl)
        row = QWidget()
        h = QHBoxLayout(row)
        h.setContentsMargins(0, 0, 0, 0)
        h.addStretch(1)
        close = QPushButton("Close")
        close.setCursor(Qt.PointingHandCursor)
        close.clicked.connect(self.close)
        h.addWidget(close)
        self.body_layout.addWidget(row)

    def _step_error(self) -> None:
        self._title("Failed")
        lbl = QLabel(self._error or "unknown error")
        lbl.setProperty("role", "err")
        lbl.setWordWrap(True)
        self.body_layout.addWidget(lbl)
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
            self.failed.emit(str(e))
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
            kind = msg.get("type")
            if kind == "log":
                self.log_msg.emit(msg.get("level") or "text", msg.get("text") or "")
            elif kind == "stage":
                self.stage_msg.emit(msg)
            elif kind == "done":
                self.done_msg.emit(msg)
            elif kind == "error":
                self.failed.emit(msg.get("message") or "build failed")
        err = (proc.stderr.read() if proc.stderr else "").strip()
        rc = proc.wait()
        if rc != 0:
            self.failed.emit(err or f"build failed (exit {rc})")

    # ── helper messages ────────────────────────────────────────────────
    def _log_color(self, level: str) -> str:
        return {
            "dim": self.p.dim, "info": self.p.accent, "ok": self.p.accent2,
            "warn": self.p.warn, "err": self.p.err, "title": self.p.accent,
        }.get(level, self.p.fg)

    def _append(self, level: str, text: str) -> None:
        color = self._log_color(level if level else "text")
        self.log.append(f'<span style="color:{color};">{escape(text)}</span>')
        self.log.moveCursor(QTextCursor.End)

    def _on_stage(self, msg: dict) -> None:
        self._stage = msg.get("name") or ""
        self.stage_lbl.setText(msg.get("label") or self._stage)
        self.bar.setValue(int(core.stage_fraction(self._stage) * 100))
        self.bar.setFormat("building ISO\u2026" if self._stage == "iso" else "")

    def _on_done(self, msg: dict) -> None:
        self._result = msg
        self.advance("done")

    def _fail(self, msg: str) -> None:
        self._error = msg
        self.advance("error")


def main(argv: list[str] | None = None) -> int:
    app = QApplication.instance() or QApplication(argv if argv is not None else sys.argv)
    app.setApplicationName("hyprtk-iso-creator")
    app.setDesktopFileName("hyprtk-iso-creator")
    app.setStyle("Fusion")
    win = Window()
    win.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
