"""CSS generation for desktop widgets.

Each desktop widget is its own layer-shell surface with its own ``Gtk.CssProvider``
added for the screen. Because every widget shares one screen-wide CSS cascade,
the rules are scoped under a per-widget class (``.widget-clock``,
``.widget-weather``, ``.widget-visualizer``) so two widgets with different
backgrounds/opacities never fight over the same selector.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.theme
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

from ..colors import rgba


def _pick(block: dict, key: str, palette: dict, fallback: str) -> str:
    """The widget's own colour override, else the palette's, else *fallback*."""
    value = str(block.get(key) or "").strip()
    if value:
        return value
    return palette.get(fallback) or fallback


def _clock_css(prefix: str, fg: str, accent: str, block: dict) -> str:
    scale = _scale(block)
    time_px = max(18, int(round(46 * scale)))
    date_px = max(9, int(round(13 * scale)))
    words_px = max(14, int(round(26 * scale)))
    dial_px = max(8, int(round(12 * scale)))
    return f"""
{prefix} .clock-time {{
  font-size: {time_px}px;
  font-weight: bold;
  color: {accent};
  letter-spacing: 1px;
}}
{prefix} .clock-date {{
  font-size: {date_px}px;
  opacity: 0.8;
  color: {fg};
}}
{prefix} .clock-words {{
  font-size: {words_px}px;
  font-weight: bold;
  color: {accent};
}}
{prefix} .clock-dial-label {{
  font-size: {dial_px}px;
  opacity: 0.8;
  color: {fg};
}}
{prefix} .clock-dial-value {{
  font-size: {dial_px}px;
  font-weight: bold;
  color: {accent};
}}
"""


def _weather_css(prefix: str, fg: str, accent: str, block: dict) -> str:
    return f"""
{prefix} .weather-icon {{ color: {accent}; }}
{prefix} .weather-temp {{
  font-size: 34px;
  font-weight: bold;
  color: {fg};
}}
{prefix} .weather-city {{ font-size: 13px; opacity: 0.85; color: {fg}; }}
{prefix} .weather-condition {{ font-size: 14px; color: {accent}; }}
{prefix} .weather-detail {{ font-size: 12px; opacity: 0.85; color: {fg}; }}
{prefix} .weather-detail-value {{ font-weight: bold; color: {fg}; }}
{prefix} .weather-forecast-day {{ font-size: 11px; opacity: 0.8; color: {fg}; }}
{prefix} .weather-forecast-hi {{ font-size: 12px; font-weight: bold; color: {fg}; }}
{prefix} .weather-forecast-lo {{ font-size: 12px; opacity: 0.7; color: {fg}; }}
{prefix} .weather-error {{ font-size: 12px; color: {fg}; opacity: 0.7; }}
"""


def _visualizer_css(prefix: str, block: dict) -> str:
    radius = max(0, int(block.get("radius", 16) or 0))
    return f"""
{prefix} .visualizer-area {{ border-radius: {max(radius - 6, 0)}px; }}
"""


def _scale(block: dict) -> float:
    try:
        return max(0.4, min(3.0, float(block.get("scale", 1.0) or 1.0)))
    except (TypeError, ValueError):
        return 1.0


def build_widget_css(widget_id: str, palette: dict, cfg: dict, block: dict) -> str:
    """The full stylesheet for one desktop widget surface."""
    block = block or {}
    fg = _pick(block, "foreground", palette, "foreground")
    accent = _pick(block, "accent", palette, "accent")
    background = _pick(block, "background", palette, "background")
    try:
        opacity = max(0.0, min(1.0, float(block.get("opacity", 0.75))))
    except (TypeError, ValueError):
        opacity = 0.75
    radius = max(0, int(block.get("radius", 16) or 0))
    padding = max(0, int(block.get("padding", 16) or 0))
    font = str(block.get("font") or "").strip() or palette.get("font")
    font_rule = f"  font-family: {font};\n" if font else ""

    prefix = f".widget-{widget_id}"
    css = f"""
{prefix}.desktop-widget {{
  background-color: {rgba(background, opacity)};
  border: 1px solid {rgba(fg, 0.12)};
  border-radius: {radius}px;
  padding: {padding}px;
  color: {fg};
{font_rule}}}
{prefix} .widget-muted {{ opacity: 0.7; }}
{prefix} .widget-icon {{ color: {accent}; }}
"""
    if widget_id == "clock":
        css += _clock_css(prefix, fg, accent, block)
    elif widget_id == "weather":
        css += _weather_css(prefix, fg, accent, block)
    elif widget_id == "visualizer":
        css += _visualizer_css(prefix, block)
    return css
