"""Shared colour helpers: parsing, contrast, blending.

Consolidates the duplicate hex/rgb parsers and the divergent ``_contrast_fg``
implementations (YIQ luma vs WCAG relative luminance) into one place so text
contrast is identical across the bar, the menu, the arc menu and the themer.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · colors
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import re


def hex_to_rgb(hex_color) -> tuple[int, int, int] | None:
    """(r, g, b) ints from #rgb/#rrggbb/#rrggbbaa; None when unparseable."""
    if not isinstance(hex_color, str):
        return None
    h = hex_color.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) < 6:
        return None
    try:
        return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    except ValueError:
        return None


def css_rgb(css_color) -> tuple[int, int, int] | None:
    """(r, g, b) ints from a #hex or rgb()/rgba() CSS colour; None if unparseable."""
    if not css_color:
        return None
    if css_color.startswith("#"):
        return hex_to_rgb(css_color)
    m = re.search(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", css_color, re.I)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    return None


def _linear(c: int) -> float:
    s = c / 255.0
    return s / 12.92 if s <= 0.04045 else ((s + 0.055) / 1.055) ** 2.4


def relative_luminance(rgb: tuple[int, int, int]) -> float:
    """WCAG relative luminance of an (r, g, b) tuple."""
    r, g, b = rgb
    return 0.2126 * _linear(r) + 0.7152 * _linear(g) + 0.0722 * _linear(b)


def contrast_fg(color, on_error: str = "#000000") -> str:
    """Black or white text that contrasts with the given #hex/rgb() colour.

    Uses WCAG relative luminance (``> 0.179`` => black text) — the same formula
    everywhere, so a mid-tone accent flips identically across the bar, the menu,
    the arc menu and the themer.
    """
    rgb = css_rgb(color)
    if rgb is None:
        return on_error
    return "#000000" if relative_luminance(rgb) > 0.179 else "#ffffff"


def rgba(color, alpha: float) -> str:
    """An ``rgba(r, g, b, a)`` CSS string from a #hex/rgb()/rgba() colour.

    ``alpha`` replaces whatever alpha the source colour had. Unparseable input
    is returned unchanged so a bad colour never breaks the stylesheet.
    """
    color = color.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", color)
    if m:
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        return f"rgba({int(h[0:2], 16)}, {int(h[2:4], 16)}, {int(h[4:6], 16)}, {alpha:.2f})"
    m = re.search(r"rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,\s*([\d.]+)\s*\)", color, re.I)
    if m:
        r, g, b = int(m.group(1)), int(m.group(2)), int(m.group(3))
        return f"rgba({r}, {g}, {b}, {alpha:.2f})"
    m = re.search(r"rgb\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*\)", color, re.I)
    if m:
        return f"rgba({int(m.group(1))}, {int(m.group(2))}, {int(m.group(3))}, {alpha:.2f})"
    return color


def hover_color(color) -> str:
    """A translucent hover colour, preserving the source's own alpha.

    Hex colours get a subtle default alpha; ``rgb()``/``rgba()`` values are
    kept as-is so imported-theme hover colours (already translucent) are not
    made opaque.
    """
    color = color.strip()
    if color.startswith("#"):
        return rgba(color, 0.12)
    if color.lower().startswith("rgb"):
        return color
    return "rgba(255, 255, 255, 0.12)"


def blend(foreground, background, alpha: float) -> str:
    """Composite ``foreground`` at ``alpha`` over ``background`` (both hex)."""
    fg = hex_to_rgb(foreground)
    bg = hex_to_rgb(background)
    if fg is None:
        return background
    if bg is None:
        bg = (0, 0, 0)
    r, g, b = (round(fg[i] * alpha + bg[i] * (1 - alpha)) for i in range(3))
    return "#%02x%02x%02x" % (r, g, b)
