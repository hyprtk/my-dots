"""Headless smoke test for the Qt GUI.

Runs the wizard's UI steps under the offscreen Qt platform. No root, no
subprocess: it only proves the Qt widgets construct and the palette/QSS build.
The option/log logic is covered by test_core.
"""

from __future__ import annotations

import os
import unittest

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("HYPRTK_ISO_TEST", "1")

try:
    from PySide6.QtWidgets import QApplication

    from hyprtk_isocreator import gui
    from hyprtk_isocreator.ui import Palette

    HAVE_QT = True
except Exception:  # pragma: no cover - exercised only without PySide6
    HAVE_QT = False


@unittest.skipUnless(HAVE_QT, "PySide6 not available")
class GuiSmokeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def test_qss_builds_from_palette(self) -> None:
        qss = gui.build_qss(Palette())
        self.assertIn("QFrame#panel", qss)
        self.assertIn("QTextEdit#log", qss)

    def test_all_steps_construct(self) -> None:
        win = gui.Window()
        for step in ("source", "output", "options", "review", "progress", "done", "error"):
            win._error = "boom"
            win.step = step
            try:
                win.show_step()
            except Exception as exc:  # noqa: BLE001
                self.fail(f"step {step!r} failed to construct: {exc}")
        win.close()

    def test_log_append_colors(self) -> None:
        win = gui.Window()
        win.step = "progress"
        win.show_step()
        win._append("warn", "careful <x>")
        self.assertIn("careful", win.log.toPlainText())
        win.close()


if __name__ == "__main__":
    unittest.main()
