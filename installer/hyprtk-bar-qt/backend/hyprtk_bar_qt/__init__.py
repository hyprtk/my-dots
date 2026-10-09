"""hyprtk-bar-qt backend — the Python/IPC logic side of the Qt rewrite.

Toolkit-free: this package never imports Qt/PySide. It is driven by the QML
shell over Quickshell's Process/IPC (JSON lines on stdout), so the same logic
can be exercised headlessly and unit-tested without a compositor.
"""

__version__ = "0.40.0"
