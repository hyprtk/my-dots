"""Import a hyprtk theme (waybar-style CSS) and resolve it into a bar palette.

Themes are imported (folder with ``style.css``, usually plus ``colors.css``)
into the bar's own themes directory: ``~/.config/hyprtk-bar/themes/``.

``@import`` and ``@define-color`` are resolved (including pywal CSS files such
as ``~/.cache/wal/colors-waybar*.css``), so an imported theme that pulls in
pywal colors re-themes live whenever the wallpaper changes.

The palette is derived from the theme's CSS:
  background/foreground -> ``window#waybar`` (solidified)
  accent                -> a real accent color (define-colors / wal color)
  hover                 -> ``#workspaces button:hover`` (alpha preserved)
The font family is NOT taken from the theme — the bar uses the system font so
pywal and imported themes render identically.
"""

# ─────────────────────────────────────────────────────────────────
#   HYPRTK · hyprtk-bar · theme_import
#   Part of the Hyprtk desktop suite · github.com/hyprtk
# ─────────────────────────────────────────────────────────────────

from __future__ import annotations

import logging
import re
import shutil
from pathlib import Path

from .config import load_pywal_colors  # noqa: E402

log = logging.getLogger("hyprtk_bar.theme_import")

BAR_THEMES_DIR = Path.home() / ".config" / "hyprtk-bar" / "themes"

_COLOR_TOKEN = re.compile(
    r"#[0-9a-fA-F]{3,8}\b|rgba?\([^)]*\)|alpha\([^)]*\)"
)
_IMPORT_RE = re.compile(
    r"@import\s+(?:url\(\s*)?[\"']?([^\"');]+)[\"']?\s*\)?\s*;"
)
_DEFINE_RE = re.compile(r"@define-color\s+([\w-]+)\s+([^;]+);")
_BLOCK_RE = re.compile(r"([^{}]+)\{([^{}]*)\}")


def find_themes_dir() -> Path:
    """Return the bar's own themes directory (created on demand)."""
    BAR_THEMES_DIR.mkdir(parents=True, exist_ok=True)
    return BAR_THEMES_DIR


def list_themes() -> list[str]:
    """Return sorted imported theme names (folders with a style.css)."""
    base = find_themes_dir()
    return sorted(
        d.name for d in base.iterdir()
        if d.is_dir() and (d / "style.css").is_file()
    )


def find_installed_themes() -> list[tuple[str, Path]]:
    """Scan common locations for importable waybar-style theme folders.

    Returns ``(name, path)`` pairs sorted by name. Themes already imported
    into the bar's own ``themes/`` directory are omitted so the list only
    shows what can still be added.
    """
    home = Path.home()
    bases = [
        home / ".config" / "waybar",
        home / ".config" / "waybar" / "themes",
        home / "hyprtk" / "configs" / "waybar" / "themes",
        home / ".config" / "waybar" / "themes",
        home / ".local" / "share" / "waybar",
        home / "Downloads",
        home / "Documents" / "GitHub",
    ]
    found: dict[str, Path] = {}

    def consider(path: Path) -> None:
        try:
            if path.is_dir() and (path / "style.css").is_file():
                found.setdefault(path.name, path)
        except OSError:
            pass

    seen: set[Path] = set()
    for base in bases:
        if base in seen:
            continue
        seen.add(base)
        if not base.is_dir():
            continue
        consider(base)
        try:
            children = sorted(base.iterdir())
        except OSError:
            continue
        for child in children:
            if not child.is_dir():
                continue
            consider(child)
            # dotfiles repos: <repo>/waybar/themes or <repo>/configs/waybar/themes
            for nested in (
                child / "waybar" / "themes",
                child / "configs" / "waybar" / "themes",
            ):
                if not nested.is_dir():
                    continue
                try:
                    for theme in sorted(nested.iterdir()):
                        consider(theme)
                except OSError:
                    pass

    imported = set(list_themes())
    return sorted(
        ((name, path) for name, path in found.items() if name not in imported),
        key=lambda item: item[0].lower(),
    )


def remove_theme(name: str) -> bool:
    """Delete an imported theme folder from the bar's themes directory.

    Refuses traversal-style names and anything resolving outside the themes
    dir. Returns True on success.
    """
    theme_dir = _safe_theme_dir(name)
    if theme_dir is None or not theme_dir.is_dir():
        return False
    try:
        theme_dir.resolve().relative_to(find_themes_dir().resolve())
    except ValueError:
        return False
    try:
        shutil.rmtree(theme_dir)
    except OSError as exc:
        log.warning("could not remove theme %s: %s", name, exc)
        return False
    return True


def import_theme(path) -> str | None:
    """Import a waybar theme folder (or a single style.css) into the bar.

    ``@import`` paths that point outside the theme (e.g. pywal's
    ``~/.cache/wal`` CSS) are rewritten to absolute paths, because moving the
    theme breaks the relative depth. Returns the theme name on success.
    """
    path = Path(path)
    base = find_themes_dir()
    if path.is_dir():
        name = path.name
        if not _safe_name(name):
            log.warning("refusing unsafe theme name %r", name)
            return None
        dest = base / name
        dest.mkdir(parents=True, exist_ok=True)
        for fname in ("style.css", "colors.css", "config"):
            src = path / fname
            if src.is_file():
                try:
                    shutil.copy2(src, dest / fname)
                except OSError as exc:
                    log.warning("could not copy %s: %s", src, exc)
        _absolutize_theme_files(dest, path)
    elif path.is_file() and path.suffix.lower() == ".css":
        name = path.stem
        if not _safe_name(name):
            log.warning("refusing unsafe theme name %r", name)
            return None
        dest = base / name
        dest.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copy2(path, dest / "style.css")
        except OSError as exc:
            log.warning("could not copy %s: %s", path, exc)
            return None
        _absolutize_theme_files(dest, path.parent)
    else:
        log.warning("not a waybar theme: %s", path)
        return None
    return name if (dest / "style.css").is_file() else None


def _absolutize_theme_files(dest: Path, origin_dir: Path) -> None:
    """Rewrite @import paths in copied CSS so files outside the theme resolve."""
    for fname in ("style.css", "colors.css"):
        target_file = dest / fname
        if not target_file.is_file():
            continue
        try:
            text = target_file.read_text(errors="replace")
        except OSError:
            continue
        rewritten = _absolutize_imports(text, origin_dir)
        if rewritten != text:
            try:
                target_file.write_text(rewritten)
            except OSError as exc:
                log.warning("could not rewrite imports in %s: %s", target_file, exc)


def _absolutize_imports(css: str, origin_dir: Path) -> str:
    """Return ``css`` with out-of-theme @import paths made absolute (~/...)."""
    home = Path.home()

    def repl(match) -> str:
        imp = match.group(1).strip()
        if imp.startswith("~") or imp.startswith("/"):
            return match.group(0)
        target = (origin_dir / imp).resolve()
        if not target.is_file():
            return match.group(0)
        try:
            target.relative_to(origin_dir)  # copied alongside: keep relative
            return match.group(0)
        except ValueError:
            pass
        try:
            newpath = f"~/{target.relative_to(home)}"
        except ValueError:
            newpath = str(target)
        return match.group(0).replace(match.group(1), newpath, 1)

    return _IMPORT_RE.sub(repl, css)


# ── CSS reading ─────────────────────────────────────────────────

def _resolve_import(origin: Path, imp: str) -> Path | None:
    if imp.startswith("~"):
        target = Path(imp).expanduser()
    elif imp.startswith("/"):
        target = Path(imp)
    else:
        target = (origin.parent / imp).resolve()
        if not target.is_file():
            # Waybar themes use relative @imports (e.g. "../../../../../.cache/wal")
            # that assume a particular deploy depth. When the depth doesn't match
            # the bar's themes dir, fall back to the home-relative remainder so
            # `~/.cache/wal/...` imports still resolve.
            rest = re.sub(r"^(?:\.\./|\./)+", "", imp)
            target = (Path.home() / rest).resolve()
    if target.is_file():
        return target
    return None


def _read_with_imports(path: Path, _seen: set | None = None) -> str:
    _seen = _seen or set()
    if path in _seen:
        return ""
    _seen.add(path)
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return ""
    parts, pos = [], 0
    for match in _IMPORT_RE.finditer(text):
        parts.append(text[pos:match.start()])
        target = _resolve_import(path, match.group(1).strip())
        if target is not None:
            parts.append(_read_with_imports(target, _seen))
        pos = match.end()
    parts.append(text[pos:])
    return "".join(parts)


def _read_theme_css(theme_dir: Path) -> str:
    css = _read_with_imports(theme_dir / "style.css")
    colors_css = theme_dir / "colors.css"
    if colors_css.is_file():
        css += "\n" + _read_with_imports(colors_css)
    return css


def _parse_define_colors(css: str) -> dict[str, str]:
    colors = dict(_DEFINE_RE.findall(css))
    for _ in range(5):  # resolve @define-color foo @bar chains
        changed = False
        for name, value in list(colors.items()):
            m = re.fullmatch(r"@([\w-]+)", value.strip())
            if m and m.group(1) in colors:
                colors[name] = colors[m.group(1)]
                changed = True
        if not changed:
            break
    return colors


def _strip_comments(css: str) -> str:
    return re.sub(r"/\*.*?\*/", "", css, flags=re.S)


def _css_blocks(css: str) -> dict[str, str]:
    cleaned = _strip_comments(css)
    # @define-color is parsed separately; leaving it in the text would merge it
    # into the next selector (e.g. the `*` rule), hiding that rule from blocks.
    cleaned = re.sub(r"@define-color\s+[\w-]+\s+[^;]+;", "", cleaned)
    blocks: dict[str, str] = {}
    for match in _BLOCK_RE.finditer(cleaned):
        selector = " ".join(match.group(1).split())
        body = match.group(2).strip()
        if body and selector:
            blocks.setdefault(selector, body)
    return blocks


# ── color resolution ────────────────────────────────────────────

def _resolve_value(value: str, colors: dict[str, str]) -> str | None:
    """Turn a CSS color value (possibly @name / alpha() / hex) into a usable color."""
    value = value.strip()
    if not value:
        return None
    if value.lower() in ("transparent", "none"):
        return None
    if value.lower() in ("white", "black"):
        return {"white": "#ffffff", "black": "#000000"}[value.lower()]
    if value.startswith("#") or value.startswith("rgb"):
        return value
    m = re.fullmatch(r"alpha\(\s*([^,]+)\s*,\s*([\d.]+)\s*\)", value, re.I)
    if m:
        base = _resolve_value(m.group(1), colors)
        rgba = _to_rgba_tuple(base)
        if rgba:
            r, g, b = rgba
            return f"rgba({r}, {g}, {b}, {float(m.group(2)):.2f})"
    m = re.fullmatch(r"@([\w-]+)", value)
    if m and m.group(1) in colors:
        return _resolve_value(colors[m.group(1)], colors)
    return None


def _to_rgba_tuple(color: str | None) -> tuple[int, int, int] | None:
    if not color:
        return None
    color = color.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", color)
    if m:
        h = m.group(1)
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        try:
            return int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
        except ValueError:
            return None
    m = re.search(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", color)
    if m:
        return int(m.group(1)), int(m.group(2)), int(m.group(3))
    return None


def _solid(color: str) -> str:
    """Return an opaque version of a color (strip its alpha)."""
    color = color.strip()
    m = re.fullmatch(r"#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})", color)
    if m:
        h = m.group(1)
        if len(h) in (3, 4):
            h = "".join(c * 2 for c in h)
        return f"#{h[0:6]}"
    m = re.search(r"rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)", color)
    if m:
        return f"rgba({int(m.group(1))}, {int(m.group(2))}, {int(m.group(3))}, 1.00)"
    return color


def _color_alpha(color: str | None) -> float | None:
    """Return a translucent rgba() alpha (0 <= a < 1), else None."""
    if not color:
        return None
    m = re.search(
        r"rgba\(\s*[\d.]+\s*,\s*[\d.]+\s*,\s*[\d.]+\s*,\s*([\d.]+)\s*\)", color, re.I
    )
    if m:
        try:
            alpha = float(m.group(1))
        except ValueError:
            return None
        return alpha if 0.0 <= alpha < 1.0 else None
    return None


def _prop(body: str, name: str) -> str | None:
    m = re.search(rf"\b{name}\s*:\s*([^;]+);", body)
    return m.group(1).strip() if m else None


def _length_px(value: str | None) -> float | None:
    m = re.fullmatch(r"([\d.]+)px", (value or "").strip())
    return float(m.group(1)) if m else None


def _length(body: str | None, name: str) -> float | None:
    return _length_px(_prop(body or "", name))


def _padding(body: str | None) -> list[float] | None:
    """Parse `padding` into 1-4 length values (px), or None."""
    value = _prop(body or "", "padding")
    if not value:
        return None
    nums = [n for p in value.split() if (n := _length_px(p)) is not None]
    return nums or None


def _border(body: str | None, colors: dict[str, str]) -> tuple[float | None, str | None]:
    """Return (width_px, color) of ``window#waybar``'s border, or (None, None)."""
    value = _prop(body or "", "border")
    if value:
        v = value.strip()
        if v.lower() in ("none", "0"):
            return None, None
        m = re.fullmatch(r"([\d.]+)px\s+(?:[a-z]+)\s+(.+)", v, re.I)
        if m:
            color = _resolve_value(m.group(2).strip(), colors)
            if color:
                return float(m.group(1)), color
    for edge in ("border-top", "border-bottom"):
        ev = _prop(body or "", edge)
        if not ev:
            continue
        em = re.fullmatch(r"([\d.]+)px\s+(?:[a-z]+)\s+(.+)", ev.strip(), re.I)
        color = _resolve_value(em.group(2).strip(), colors) if em else _resolve_value(ev.strip(), colors)
        if color:
            return (float(em.group(1)) if em else 1), color
    width = _length(body, "border-width")
    color = _resolve_value(_prop(body or "", "border-color") or "", colors)
    if width and color:
        return width, color
    return None, None


def _background_color(body: str, colors: dict[str, str]) -> str | None:
    value = _prop(body, "background") or _prop(body, "background-color")
    if not value:
        return None
    if "gradient" in value.lower():
        tokens = [t for t in _COLOR_TOKEN.findall(value)]
        if tokens:
            # gradients end in the darkest stop: take the last resolvable token
            for token in reversed(tokens):
                resolved = _resolve_value(token, colors)
                if resolved:
                    return resolved
    return _resolve_value(value, colors)


def _text_color(body: str, colors: dict[str, str]) -> str | None:
    return _resolve_value(_prop(body, "color") or "", colors)


# ── palette extraction ──────────────────────────────────────────

# Theme names come from the (user-writable) bar config; refuse anything that
# could escape the themes dir via ../.
_THEME_NAME_RE = re.compile(r"^[A-Za-z0-9_.+-]+$")


def _safe_name(name: str) -> bool:
    """True when *name* is a sane theme dir name (no traversal / separators)."""
    return bool(name) and _THEME_NAME_RE.fullmatch(name) is not None


def _safe_theme_dir(theme_name: str):
    """Resolve a theme directory, refusing traversal-style names."""
    if not theme_name or not _THEME_NAME_RE.fullmatch(theme_name):
        return None
    return find_themes_dir() / theme_name


def parse_palette(theme_name: str) -> dict | None:
    """Parse an imported theme into a hyprtk-bar palette dict, or None."""
    theme_dir = _safe_theme_dir(theme_name)
    if theme_dir is None:
        return None
    if not (theme_dir / "style.css").is_file():
        return None
    css = _read_theme_css(theme_dir)
    colors = _parse_define_colors(css)
    # Overlay the LIVE pywal palette onto the theme's @colorN definitions.
    # Imported themes reference colors-waybar*.css files which may be stale
    # (e.g. a theme importing a custom css that nothing regenerates after a
    # wallpaper change). colors.json is always current, so this makes the
    # theme's pywal-derived colors track the active wallpaper.
    pywal_live = load_pywal_colors()
    if pywal_live:
        colors.update(pywal_live)
    blocks = _css_blocks(css)
    win_body = blocks.get("window#waybar")

    def pick(kind: str, selector: str) -> str | None:
        body = blocks.get(selector)
        if body:
            if kind == "background":
                return _background_color(body, colors)
            return _text_color(body, colors)
        return None

    bg_value = (
        pick("background", "window#waybar")
        or colors.get("background")
        or colors.get("color0")
        or "#1a1b26"
    )
    background = _solid(bg_value)
    background_alpha = _color_alpha(bg_value)
    foreground = _solid(
        pick("color", "window#waybar")
        or colors.get("foreground")
        or colors.get("color7")
        or "#c0caf5"
    )
    border_width, border_color = _border(win_body, colors)
    accent = _solid(
        colors.get("accent")
        or colors.get("color5")
        or colors.get("color4")
        or colors.get("mauve")
        or colors.get("sky")
        or border_color  # the theme's bar border is a strong accent signal
        or pick("background", "#workspaces button.focused")
        or pick("background", "#workspaces button.active")
        or foreground
    )
    hover = (
        pick("background", "#workspaces button:hover")
        or "rgba(255, 255, 255, 0.08)"
    )

    palette = {
        "background": background,
        "foreground": foreground,
        "accent": accent,
        "hover": hover,
        "running": accent,
    }
    if background_alpha is not None:
        palette["background_alpha"] = background_alpha
    # Font-family is intentionally NOT taken from the theme: the bar uses the
    # system font (the same one the pywal theme renders with), so switching
    # between pywal and imported themes never changes the font type.
    if border_width is not None and border_color:
        palette["border_width"] = border_width
        palette["border_color"] = border_color
    # Optional glass effects (drop shadow / specular rim) from window#waybar.
    bar_shadow = _prop(win_body, "box-shadow")
    if bar_shadow:
        palette["bar_shadow"] = bar_shadow
    radius = _length(win_body, "border-radius")
    if radius is not None:
        palette["border_radius"] = radius
    spacing = _length(win_body, "spacing")
    if spacing is not None:
        palette["spacing"] = spacing
    padding = _padding(win_body)
    if padding:
        palette["padding"] = padding

    # base font-size (window#waybar or the `*` rule); fall back to the theme's
# module font-size (#workspaces button / #clock / #tray) when the bar rules
# don't set one — waybar themes size their text on the modules.
    font_size = _length(win_body, "font-size") or _length(blocks.get("*"), "font-size")
    if font_size is None:
        for sel in ("#workspaces button", "#clock", "#tray", "#workspaces"):
            fs = _length(blocks.get(sel), "font-size")
            if fs is not None:
                font_size = fs
                break
    if font_size is not None:
        palette["font_size"] = font_size

    # ── workspace chips (#workspaces button) ─────────────────────
    chip = blocks.get("#workspaces button")
    if chip:
        pad = _padding(chip)
        if pad:
            palette["chip_padding"] = pad
        cradius = _length(chip, "border-radius")
        if cradius is not None:
            palette["chip_radius"] = cradius
        cwidth, ccolor = _border(chip, colors)
        if cwidth is not None and ccolor:
            palette["chip_border_width"] = cwidth
            palette["chip_border_color"] = ccolor
        # Chip backgrounds keep their alpha — waybar themes use translucent
        # highlights that look wrong when solidified to opaque.
        cbg = _background_color(chip, colors)
        if cbg and cbg.strip().lower() not in ("transparent", "none"):
            palette["chip_bg"] = cbg
        cfg_color = _text_color(chip, colors)
        if cfg_color:
            palette["chip_fg"] = cfg_color
        csize = _length(chip, "font-size")
        if csize is not None:
            palette["chip_font_size"] = csize
        weight = _prop(chip, "font-weight")
        if weight and weight.strip().lower() not in ("normal", ""):
            palette["chip_font_weight"] = weight.strip()

    # active / focused chip
    for sel in ("#workspaces button.focused", "#workspaces button.active"):
        body = blocks.get(sel)
        if not body:
            continue
        bg = _background_color(body, colors)
        if bg and bg.strip().lower() not in ("transparent", "none"):
            palette.setdefault("active_bg", bg)
        fg = _text_color(body, colors)
        if fg:
            palette.setdefault("active_fg", fg)
        shadow = _prop(body, "box-shadow")
        if shadow:
            palette.setdefault("active_shadow", shadow)

    # occupied chip
    occ = blocks.get("#workspaces button.occupied")
    if occ:
        fg = _text_color(occ, colors)
        if fg:
            palette["occupied_fg"] = fg

    return palette