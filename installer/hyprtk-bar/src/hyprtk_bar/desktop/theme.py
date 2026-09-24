"""CSS generation for desktop widgets.

Each desktop widget is its own layer-shell surface with its own ``Gtk.CssProvider``
added for the screen. Because every widget shares one screen-wide CSS cascade,
the rules are scoped under a per-widget class (``.widget-clock``,
``.widget-weather``, …) so two widgets with different backgrounds/opacities never
fight over the same selector.

Every widget's sizes are multiplied by an effective **scale** — the widget's own
``scale`` config, overridden by the snap layout's fit scale (see
``DesktopWidgetManager``) so a snapped group's content scales to its uniform
cell.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · desktop.theme
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

from ..colors import rgba


def resolve_widget_palette(cfg: dict) -> dict:
    """The palette desktop widgets theme from: **pywal by default**.

    Widgets follow the live pywal wallpaper palette out of the box, whatever the
    bar's own theme source is (pywal / imported / manual). A widget's explicit
    ``background`` / ``foreground`` / ``accent`` still wins — ``build_widget_css``
    prefers those over the palette.
    """
    from ..config import load_pywal_colors
    from ..theme import resolve_palette

    palette = dict(resolve_palette(cfg))
    pywal = load_pywal_colors()
    if pywal:
        palette["background"] = pywal.get("background") or palette.get("background")
        palette["foreground"] = pywal.get("foreground") or palette.get("foreground")
        palette["accent"] = pywal.get("color5") or pywal.get("color4") or palette.get("accent")
    return palette


def _pick(block: dict, key: str, palette: dict, fallback: str) -> str:
    """The widget's own colour override, else the palette's, else *fallback*."""
    value = str(block.get(key) or "").strip()
    if value:
        return value
    return palette.get(fallback) or fallback


def _scale(block: dict) -> float:
    try:
        return max(0.4, min(3.0, float(block.get("scale", 1.0) or 1.0)))
    except (TypeError, ValueError):
        return 1.0


def _px(base: float, scale: float) -> int:
    return max(8, int(round(base * scale)))


def _progress_css(prefix: str, fg: str, accent: str, scale: float) -> str:
    bar_h = _px(6, scale)
    radius = max(1, bar_h // 2)
    return f"""
{prefix} progressbar.widget-progress {{
  min-height: {bar_h}px;
  border-radius: {radius}px;
  background-color: transparent;
}}
{prefix} progressbar.widget-progress trough {{
  min-height: {bar_h}px;
  border-radius: {radius}px;
  border: none;
  background-color: {rgba(fg, 0.14)};
}}
{prefix} progressbar.widget-progress progress {{
  min-height: {bar_h}px;
  border-radius: {radius}px;
  border: none;
  background-color: {accent};
}}
{prefix} progressbar.widget-progress text {{ color: transparent; }}
"""


def _clock_css(prefix: str, fg: str, accent: str, scale: float) -> str:
    return f"""
{prefix} .clock-time {{
  font-size: {_px(46, scale)}px;
  font-weight: bold;
  color: {accent};
  letter-spacing: 1px;
}}
{prefix} .clock-date {{
  font-size: {_px(13, scale)}px;
  opacity: 0.8;
  color: {fg};
}}
{prefix} .clock-words {{
  font-size: {_px(26, scale)}px;
  font-weight: bold;
  color: {accent};
}}
{prefix} .clock-dial-label {{
  font-size: {_px(12, scale)}px;
  opacity: 0.8;
  color: {fg};
}}
{prefix} .clock-dial-value {{
  font-size: {_px(12, scale)}px;
  font-weight: bold;
  color: {accent};
}}
"""


def _weather_css(prefix: str, fg: str, accent: str, scale: float) -> str:
    return f"""
{prefix} .weather-icon {{ color: {accent}; }}
{prefix} .weather-temp {{
  font-size: {_px(34, scale)}px;
  font-weight: bold;
  color: {fg};
}}
{prefix} .weather-city {{ font-size: {_px(13, scale)}px; opacity: 0.85; color: {fg}; }}
{prefix} .weather-condition {{ font-size: {_px(14, scale)}px; color: {accent}; }}
{prefix} .weather-detail {{ font-size: {_px(12, scale)}px; opacity: 0.85; color: {fg}; }}
{prefix} .weather-detail-value {{ font-weight: bold; color: {fg}; }}
{prefix} .weather-forecast-day {{ font-size: {_px(11, scale)}px; opacity: 0.8; color: {fg}; }}
{prefix} .weather-forecast-hi {{ font-size: {_px(12, scale)}px; font-weight: bold; color: {fg}; }}
{prefix} .weather-forecast-lo {{ font-size: {_px(12, scale)}px; opacity: 0.7; color: {fg}; }}
{prefix} .weather-error {{ font-size: {_px(12, scale)}px; color: {fg}; opacity: 0.7; }}
"""


def _visualizer_css(prefix: str, block: dict) -> str:
    radius = max(0, int(block.get("radius", 16) or 0))
    return f"""
{prefix} .visualizer-area {{ border-radius: {max(radius - 6, 0)}px; }}
"""


def _disk_css(prefix: str, fg: str, accent: str, scale: float) -> str:
    return f"""
{prefix} .disk-name {{ font-size: {_px(12, scale)}px; font-weight: bold; color: {fg}; }}
{prefix} .disk-size {{ font-size: {_px(11, scale)}px; opacity: 0.85; color: {fg}; }}
{prefix} .disk-rates {{ font-size: {_px(12, scale)}px; color: {accent}; }}
{prefix} .widget-progress {{ margin-top: 1px; }}
"""


def _network_css(prefix: str, fg: str, accent: str, scale: float) -> str:
    return f"""
{prefix} .net-name {{ font-size: {_px(14, scale)}px; font-weight: bold; color: {fg}; }}
{prefix} .net-ip {{ font-size: {_px(12, scale)}px; opacity: 0.85; color: {fg}; }}
{prefix} .net-rates {{ font-size: {_px(12, scale)}px; color: {accent}; }}
{prefix} .widget-graph {{ margin-top: 2px; }}
"""


def _resources_css(prefix: str, fg: str, accent: str, scale: float) -> str:
    return f"""
{prefix} .res-key {{ font-size: {_px(12, scale)}px; opacity: 0.9; color: {fg}; }}
{prefix} .res-val {{ font-size: {_px(13, scale)}px; font-weight: bold; color: {accent}; }}
{prefix} .res-meta {{ font-size: {_px(11, scale)}px; opacity: 0.8; color: {fg}; }}
{prefix} .widget-graph {{ margin: 2px 0; }}
"""


def _sysinfo_css(prefix: str, fg: str, accent: str, scale: float) -> str:
    return f"""
{prefix} .info-key {{ font-size: {_px(12, scale)}px; opacity: 0.7; color: {fg}; }}
{prefix} .info-val {{ font-size: {_px(12, scale)}px; color: {fg}; }}
"""


def build_widget_css(
    widget_id: str, palette: dict, cfg: dict, block: dict, scale: float | None = None
) -> str:
    """The full stylesheet for one desktop widget surface.

    *scale* overrides the widget's own ``scale`` (used by the snap layout so a
    group's content fits its uniform cell).
    """
    block = block or {}
    fg = _pick(block, "foreground", palette, "foreground")
    accent = _pick(block, "accent", palette, "accent")
    background = _pick(block, "background", palette, "background")
    try:
        opacity = max(0.0, min(1.0, float(block.get("opacity", 0.75))))
    except (TypeError, ValueError):
        opacity = 0.75
    eff_scale = _scale(block) if scale is None else max(0.4, min(3.0, float(scale)))
    radius = max(0, int(block.get("radius", 16) or 0))
    padding = _px(int(block.get("padding", 16) or 0), eff_scale)
    font = str(block.get("font") or "").strip() or palette.get("font")
    font_rule = f"  font-family: {font};\n" if font else ""

    if block.get("transparent"):
        # Transparent pill: drop the background fill and border, keep the content.
        bg_rule = "background-color: transparent;"
        border_rule = "border: none;"
    else:
        bg_rule = f"background-color: {rgba(background, opacity)};"
        border_rule = f"border: 1px solid {rgba(fg, 0.12)};"

    prefix = f".widget-{widget_id}"
    css = f"""
{prefix}.desktop-widget {{
  {bg_rule}
  {border_rule}
  border-radius: {radius}px;
  padding: {padding}px;
  color: {fg};
{font_rule}}}
{prefix} .widget-muted {{ opacity: 0.7; }}
{prefix} .widget-icon {{ color: {accent}; }}
"""
    if widget_id == "clock":
        css += _clock_css(prefix, fg, accent, eff_scale)
    elif widget_id == "weather":
        css += _weather_css(prefix, fg, accent, eff_scale)
    elif widget_id == "visualizer":
        css += _visualizer_css(prefix, block)
    elif widget_id == "disk":
        css += _disk_css(prefix, fg, accent, eff_scale) + _progress_css(prefix, fg, accent, eff_scale)
    elif widget_id == "network":
        css += _network_css(prefix, fg, accent, eff_scale)
    elif widget_id == "resources":
        css += _resources_css(prefix, fg, accent, eff_scale) + _progress_css(prefix, fg, accent, eff_scale)
    elif widget_id == "sysinfo":
        css += _sysinfo_css(prefix, fg, accent, eff_scale)
    return css
