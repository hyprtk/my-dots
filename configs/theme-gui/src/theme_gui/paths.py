from pathlib import Path

HOME = Path.home()

# ── hyprtk-merged source ──────────────────────────────────────
HYPRTK = HOME / "hyprtk"
HYPRTK_SOURCE = HOME / "Projects" / "AI-Projects" / "hyprtk-merged"

# ── pywal cache ───────────────────────────────────────────────
WAL_CACHE = HOME / ".cache" / "wal"
WAL_COLORS = WAL_CACHE / "colors"
WAL_LOCK = WAL_CACHE / ".wallpaper-change.lock"

# ── live configs ──────────────────────────────────────────────
CONFIG = HOME / ".config"
WAYBAR_CONFIG = CONFIG / "waybar"
WAYBAR_THEMES = WAYBAR_CONFIG / "themes"
THEME_STYLE_CACHE = WAL_CACHE.parent / ".themestyle.sh"

ROFI_CONFIG = CONFIG / "rofi"
ROFI_VARIANTS = ROFI_CONFIG / "variants"
ROFI_VARIANT_LINK = ROFI_CONFIG / "variant.rasi"

SWAYLOCK_CONFIG = CONFIG / "swaylock" / "config"
MATUWALL_CONFIG = CONFIG / "matuwall" / "config.json"
MATUWALL_COLORS = CONFIG / "matuwall" / "colors.json"

# ── hyprtk scripts ────────────────────────────────────────────
HYPRTK_SCRIPTS = HYPRTK / "hypr" / "scripts"
WALLPAPER_COLORS_SH = HYPRTK_SCRIPTS / "wallpaper-colors.sh"
WALLPAPER_RESTORE_SH = HYPRTK_SCRIPTS / "wallpaper-restore.sh"
WAL_WATCHER_SH = HYPRTK_SCRIPTS / "wal-watcher.sh"
GENERATE_AERO_SH = HYPRTK_SCRIPTS / "generate-aero-colors.sh"
CHANGE_ICONS_SH = HYPRTK / "configs" / "papirus-icons" / "scripts" / "change-icons.sh"
WAYBAR_LAUNCH_SH = HYPRTK / "configs" / "waybar" / "launch.sh"
SYNC_ROFI_SH = HYPRTK / "configs" / "rofi" / "scripts" / "sync-rofi-theme.sh"

# ── wallpaper directories ─────────────────────────────────────
WALLPAPER_DIRS = [
    HOME / "Pictures" / "Wallpapers",
    HOME / "Pictures",
    HYPRTK / "assets" / "Wallpapers",
]

# ── swaylock pywal template ───────────────────────────────────
SWAYLOCK_WAL_TEMPLATE = HYPRTK / "configs" / "wal" / "templates" / "colors-swaylock.conf"

# ── theme-gui own config ──────────────────────────────────────
THEME_GUI_CONFIG = CONFIG / "theme-gui" / "config.json"

# ── image extensions ──────────────────────────────────────────
IMAGE_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".gif", ".bmp"}
