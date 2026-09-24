"""Desktop widgets: free-floating layer-shell surfaces owned by the bar process.

Distinct from the bar's own modules, desktop widgets are independent surfaces
(like conky panels) that can be enabled, placed and themed individually from the
settings window's "Widgets" page.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from .manager import DesktopWidgetManager

__all__ = ["DesktopWidgetManager"]
