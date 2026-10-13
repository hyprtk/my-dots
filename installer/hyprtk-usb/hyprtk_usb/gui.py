"""Qt (PySide6) front end for hyprtk-usb.

The GUI runs unprivileged and drives the same ``core`` backend as the CLI. The
single privileged operation — the write — is performed by ``hyprtk_usb.helper``
launched through ``pkexec``, so the Qt app never runs as root and isn't subject
to pkexec's stripped environment.

A frameless, non-resizable wizard over ``core``, themed from the running
hyprtk-bar palette (``palette.load_palette``). The compositor draws the pywal
border + rounding; the panel is frosted at the bar theme's opacity.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import threading

from PySide6.QtCore import Qt, Signal
from PySide6.QtGui import QColor, QIcon, QPainter
from PySide6.QtWidgets import (
    QAbstractButton,
    QApplication,
    QComboBox,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QProgressBar,
    QPushButton,
    QSizePolicy,
    QVBoxLayout,
    QWidget,
)

from . import core
from .palette import Palette, human_bytes, load_palette

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


def _rgba(hex_color: str, alpha: float) -> str:
    """A QSS ``rgba(...)`` string from a hex colour and a 0..1 alpha."""
    c = QColor(hex_color)
    if not c.isValid():
        c = QColor("#000000")
    return f"rgba({c.red()},{c.green()},{c.blue()},{int(round(alpha * 255))})"


def _arrow_icon(color: str) -> str:
    """Write a small down-chevron SVG in ``color`` to the app cache and return
    its path. Qt's QSS can't draw a border-triangle for ``QComboBox::down-arrow``
    (it renders as a filled block), so the arrow is a themed SVG."""
    cache = os.path.join(os.path.expanduser("~"), ".cache", "hyprtk-usb")
    path = os.path.join(cache, "combo-arrow.svg")
    try:
        os.makedirs(cache, exist_ok=True)
        with open(path, "w") as f:
            f.write(
                '<svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" '
                'viewBox="0 0 12 12"><path d="M2.5 4.5L6 8l3.5-3.5" fill="none" '
                f'stroke="{color}" stroke-width="2" stroke-linecap="round" '
                'stroke-linejoin="round"/></svg>'
            )
        return path
    except OSError:
        return ""


def _apply_icon_theme() -> None:
    """Use the desktop's icon theme (Papirus-Dark) so file-chooser icons match
    the session — and the pywal folder colour papirus-folders applies there."""
    name = ""
    try:
        ini = os.path.join(os.path.expanduser("~"), ".config", "gtk-3.0", "settings.ini")
        with open(ini) as f:
            for line in f:
                if line.strip().startswith("gtk-icon-theme-name"):
                    name = line.split("=", 1)[1].strip()
                    break
    except OSError:
        pass
    QIcon.setThemeName(name or "Papirus-Dark")


def build_qss(p: Palette) -> str:
    """The hyprtk usb stylesheet: a pywal-driven frosted panel with mauve
    (color5) accents and cyan (color6) surface tints. Matches the bar's look.
    """
    arrow = _arrow_icon(p.accent)
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

QComboBox {{
    background-color: {_rgba(p.accent2, 0.08)};
    color: {p.fg};
    border: 1px solid {_rgba(p.accent2, 0.25)};
    border-radius: 10px;
    padding: 5px 10px;
}}
QComboBox:hover {{ background-color: {_rgba(p.accent2, 0.14)}; }}
QComboBox::drop-down {{ border: none; width: 26px; }}
QComboBox::down-arrow {{
    image: url({arrow});
    width: 12px; height: 12px;
    margin-right: 6px;
}}
QComboBox QAbstractItemView {{
    background-color: {p.bg};
    color: {p.fg};
    border: 1px solid {_rgba(p.accent, 0.45)};
    outline: 0;
    selection-background-color: {_rgba(p.accent, 0.85)};
    selection-color: #ffffff;
}}
QComboBox QAbstractItemView::item {{
    padding: 5px 8px;
    border: none;
}}
QComboBox QAbstractItemView::item:selected,
QComboBox QAbstractItemView::item:selected:active {{
    background-color: {_rgba(p.accent, 0.85)};
    color: #ffffff;
    border: none;
}}

QProgressBar {{
    background-color: {_rgba(p.accent2, 0.12)};
    border: none; border-radius: 8px;
    min-height: 10px; max-height: 10px;
    text-align: center; color: {p.fg};
}}
QProgressBar::chunk {{ background-color: {p.accent}; border-radius: 8px; }}

/* ── file dialog (non-native) — match the frosted panel ── */
QDialog, QFileDialog {{ background-color: {_rgba(p.bg, p.opacity)}; }}
QFileDialog QLabel {{ color: {p.fg}; }}
QFileDialog QListView, QFileDialog QTreeView {{
    background-color: {_rgba(p.accent2, 0.05)};
    color: {p.fg};
    border: 1px solid {_rgba(p.accent2, 0.20)};
    border-radius: 8px; outline: none;
}}
QFileDialog QListView::item, QFileDialog QTreeView::item {{ padding: 3px 6px; border-radius: 6px; }}
QFileDialog QListView::item:hover, QFileDialog QTreeView::item:hover {{ background-color: {_rgba(p.accent2, 0.15)}; }}
QFileDialog QListView::item:selected, QFileDialog QTreeView::item:selected {{ background-color: {_rgba(p.accent, 0.85)}; color: #ffffff; }}
QFileDialog QHeaderView::section {{
    background-color: {_rgba(p.accent2, 0.10)};
    color: {p.dim};
    border: none; border-bottom: 1px solid {_rgba(p.accent2, 0.20)};
    padding: 4px 6px;
}}
QFileDialog QToolButton {{
    background: transparent; border: none; border-radius: 6px;
    color: {p.fg}; padding: 4px;
}}
QFileDialog QToolButton:hover {{ background-color: {_rgba(p.accent2, 0.18)}; }}
QFileDialog QComboBox {{
    background-color: {_rgba(p.accent2, 0.08)}; color: {p.fg};
    border: 1px solid {_rgba(p.accent2, 0.25)}; border-radius: 8px; padding: 4px 8px;
}}
QFileDialog QSplitter::handle {{ background: transparent; }}
QFileDialog QScrollBar:vertical {{ background: transparent; width: 10px; margin: 2px; }}
QFileDialog QScrollBar::handle:vertical {{ background-color: {_rgba(p.accent, 0.45)}; border-radius: 5px; min-height: 24px; }}
QFileDialog QScrollBar::add-line:vertical, QFileDialog QScrollBar::sub-line:vertical {{ height: 0; }}
QFileDialog QScrollBar:horizontal {{ background: transparent; height: 10px; margin: 2px; }}
QFileDialog QScrollBar::handle:horizontal {{ background-color: {_rgba(p.accent, 0.45)}; border-radius: 5px; min-width: 24px; }}
QFileDialog QScrollBar::add-line:horizontal, QFileDialog QScrollBar::sub-line:horizontal {{ width: 0; }}
"""


class Switch(QAbstractButton):
    """A compact pill toggle."""

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
    progress_msg = Signal(dict)
    failed = Signal(str)
    finished = Signal()

    def __init__(self) -> None:
        super().__init__()
        self.setObjectName("root")
        self.setWindowTitle("hyprtk-usb")
        self.setWindowFlag(Qt.FramelessWindowHint, True)
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setFixedSize(720, 600)
        self.p = load_palette()
        self.runner = core.ExecRunner()

        self.step = "iso"
        self.iso_path = ""
        self.devices: list[core.Device] = []
        self.target = ""
        self.persist = True
        self.size = "rest"
        self.refresh = False
        self._error: str | None = None

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
        self.body_layout.setContentsMargins(18, 18, 18, 18)
        self.body_layout.setSpacing(14)
        pl.addWidget(body)

        self.progress_msg.connect(self._progress)
        self.failed.connect(self._fail)
        self.finished.connect(self._finish)
        self.show_step()

    def _header_row(self) -> QWidget:
        bar = DragBar()
        bar.setObjectName("header")
        # Keep the header at its natural height so it can't absorb extra
        # vertical space (which would float the title away from the top edge).
        bar.setSizePolicy(QSizePolicy.Preferred, QSizePolicy.Fixed)
        row = QHBoxLayout(bar)
        row.setContentsMargins(18, 16, 14, 6)
        row.setSpacing(8)
        title = QLabel("hyprtk-usb")
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
        # Visual order: primary action, then Back.
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

    # ── steps ──────────────────────────────────────────────────────────
    def show_step(self) -> None:
        self._clear()
        getattr(self, f"_step_{self.step}")()
        # Push the step content to the top; without this the vertical slack is
        # shared out and the title/dim labels stretch (and their text drifts).
        self.body_layout.addStretch(1)

    def go_back(self) -> None:
        self.step = {"device": "iso", "options": "device", "review": "options"}.get(self.step, "iso")
        self.show_step()

    def advance(self, nxt: str) -> None:
        self.step = nxt
        self.show_step()

    def _step_iso(self) -> None:
        self._title("Select the ISO", "The hyprtk ISO to write to the USB stick.")
        isos = core.scan_isos()
        combo = QComboBox()
        combo.addItems(isos)
        if isos:
            combo.setCurrentIndex(0)
            self.iso_path = isos[0]
        combo.currentTextChanged.connect(self._set_iso)
        self.body_layout.addWidget(combo)

        browse = QPushButton("Browse\u2026")
        browse.setCursor(Qt.PointingHandCursor)
        browse.clicked.connect(self._browse_iso)
        self._row("", browse)

        if not isos:
            w = QLabel("No hyprtk ISO found in ~/Documents/Isos or ~.")
            w.setProperty("role", "warn")
            self.body_layout.addWidget(w)

        self._buttons(back=False, forward=("Continue", "device"))

    def _browse_iso(self) -> None:
        # Non-native so the app stylesheet themes it (the portal dialog is not).
        dlg = QFileDialog(self, "Select ISO")
        dlg.setOption(QFileDialog.DontUseNativeDialog, True)
        dlg.setFileMode(QFileDialog.ExistingFile)
        dlg.setNameFilter("ISO images (*.iso)")
        dlg.setDirectory(os.path.expanduser("~"))
        if dlg.exec():
            files = dlg.selectedFiles()
            if files:
                self._set_iso(files[0])

    def _set_iso(self, path: str) -> None:
        self.iso_path = path
        self.devices = []
        self.target = ""

    def _step_device(self) -> None:
        self._title("Select the target disk", "Whole disks only \u2014 the stick is erased.")
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

        combo = QComboBox()
        combo.addItems([d.describe() for d in self.devices])
        combo.setCurrentIndex(0)
        self.target = self.devices[0].path
        combo.currentIndexChanged.connect(self._set_device)
        self.body_layout.addWidget(combo)
        self._buttons(back=True, forward=("Continue", "options"))

    def _set_device(self, idx: int) -> None:
        if 0 <= idx < len(self.devices):
            self.target = self.devices[idx].path

    def _step_options(self) -> None:
        self._title("Options", f"Target {self.target}")
        p = self._current_device()

        persist_sw = Switch(self.persist, self.p.accent, self.p.accent2)
        persist_sw.toggled.connect(lambda v: setattr(self, "persist", v))
        self._row("Add the hyprtk-persist partition", persist_sw)

        size_combo = QComboBox()
        size_combo.addItems(list(SIZE_CHOICES))
        size_combo.setCurrentIndex(SIZE_CHOICES.index(self.size) if self.size in SIZE_CHOICES else 0)
        size_combo.currentTextChanged.connect(lambda t: setattr(self, "size", t or "rest"))
        self._row("Persistence size", size_combo)

        if p is not None and p.persist_partition() is not None:
            refresh_sw = Switch(self.refresh, self.p.accent, self.p.accent2)
            refresh_sw.toggled.connect(lambda v: setattr(self, "refresh", v))
            self._row("Keep the existing partition", refresh_sw)
            note = QLabel("An existing hyprtk-persist partition was found.")
            note.setProperty("role", "dim")
            self.body_layout.addWidget(note)

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
                core.Options(persist=self.persist, size=self.size,
                             refresh=self.refresh, test_mode=TEST_MODE),
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
            self.body_layout.addWidget(QLabel(line))
        for w in plan.warnings:
            wl = QLabel("! " + w)
            wl.setProperty("role", "warn")
            wl.setWordWrap(True)
            self.body_layout.addWidget(wl)

        erase = QLabel(f"This ERASES {dev.path}.")
        erase.setProperty("role", "err")
        self.body_layout.addWidget(erase)

        row = QWidget()
        h = QHBoxLayout(row)
        h.setContentsMargins(0, 0, 0, 0)
        h.setSpacing(8)
        h.addStretch(1)
        write = QPushButton("Write")
        write.setProperty("role", "primary")
        write.setCursor(Qt.PointingHandCursor)
        write.clicked.connect(self._start_write)
        h.addWidget(write)
        back = QPushButton("Back")
        back.setCursor(Qt.PointingHandCursor)
        back.clicked.connect(self.go_back)
        h.addWidget(back)
        self.body_layout.addWidget(row)

    def _step_progress(self) -> None:
        self._title("Writing", "Do not unplug the device.")
        self.bar = QProgressBar()
        self.bar.setRange(0, 100)
        self.bar.setTextVisible(True)
        self.body_layout.addWidget(self.bar)
        self.status = QLabel("starting\u2026")
        self.status.setProperty("role", "dim")
        self.body_layout.addWidget(self.status)

    def _step_done(self) -> None:
        self._title("Done")
        msg = 'Boot the stick and pick "Hyprtk live with persistence".'
        lbl = QLabel(msg)
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
        self._error_label(self._error or "unknown error")
        self._buttons(back=True, forward=None)

    def _error_label(self, msg: str) -> None:
        lbl = QLabel(msg)
        lbl.setProperty("role", "err")
        lbl.setWordWrap(True)
        self.body_layout.addWidget(lbl)

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
            self.progress_msg.emit(msg)
        err = (proc.stderr.read() if proc.stderr else "").strip()
        rc = proc.wait()
        if rc != 0:
            self.failed.emit(err or f"write failed (exit {rc})")
        else:
            self.finished.emit()

    def _progress(self, msg: dict) -> None:
        stage = msg.get("stage", "")
        if stage == "copy":
            total = msg.get("total") or 0
            written = msg.get("written") or 0
            if total:
                self.bar.setValue(int(min(written / total, 1.0) * 100))
                self.bar.setFormat(f"copying {human_bytes(written)} / {human_bytes(total)}")
        elif stage == "partition":
            self.status.setText("adding the persistence partition\u2026")
        elif stage == "format":
            self.status.setText(f"formatting {core.PERSIST_LABEL}\u2026")

    def _fail(self, msg: str) -> None:
        self._error = msg
        self.advance("error")

    def _finish(self) -> None:
        self.advance("done")


def main(argv: list[str] | None = None) -> int:
    app = QApplication.instance() or QApplication(argv if argv is not None else sys.argv)
    app.setApplicationName("hyprtk-usb")
    app.setDesktopFileName("hyprtk-usb")
    app.setStyle("Fusion")
    _apply_icon_theme()
    win = Window()
    win.show()
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
