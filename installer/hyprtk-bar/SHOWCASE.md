# Showcase

Screenshots of **hyprtk-bar 0.4.4** — the GTK4-native build — on a 3840x1080
display under Hyprland, captured on an empty workspace so only the bar and its
own surfaces show. The bar is themed live from the pywal16 palette of the
current wallpaper.

All images live in [`assets/screenshots/`](assets/screenshots/).

---

## The taskbar

The default view — left section (start button, quick links, task list, active
window), centered workspaces, and the right cluster (updates, system monitor,
keyboard state, clock, notifications, tray, quick settings).

![The taskbar](assets/screenshots/bar.png)

---

## Start menu

The in-bar application menu comes in four layouts, toggled from the start
button or `Super + Space`.

| Whisker | Windows 7 |
|---------|-----------|
| ![Whisker](assets/screenshots/menu-whisker.png) | ![Windows 7](assets/screenshots/menu-win7.png) |

| Windows 11 | Plasma |
|------------|--------|
| ![Windows 11](assets/screenshots/menu-win11.png) | ![Plasma](assets/screenshots/menu-plasma.png) |

---

## Arc menu

A radial launcher overlay (Android Material style) — a FAB fans out a ring of
app shortcuts. Toggled from `Super + Ctrl + M`.

![Arc menu](assets/screenshots/arc-menu.png)

---

## Quick settings

Wi-Fi and Bluetooth toggles, a volume slider with mute, mic level, and a
brightness slider (auto-hidden when no backlight device exists).

![Quick settings](assets/screenshots/quick-settings.png)

---

## System monitor

A Mission Center-style dialog (click the CPU/RAM readout in the bar): CPU,
Memory, Disks, Network, GPU and Apps pages with live graphs and readouts.

![System monitor](assets/screenshots/system-monitor.png)

---

## Desktop widgets

Free-floating layer surfaces, independent of the bar — each one can be enabled,
placed (free or snapped into a row/column) and themed from the
[Settings → Widgets](#widgets) tabs.

| Clock | Weather |
|-------|---------|
| ![Clock widget](assets/screenshots/widget-clock.png) | ![Weather widget](assets/screenshots/widget-weather.png) |

| Audio visualizer | Hard disks |
|------------------|-----------|
| ![Audio visualizer widget](assets/screenshots/widget-visualizer.png) | ![Hard disks widget](assets/screenshots/widget-disk.png) |

| Network | Processor / RAM |
|---------|-----------------|
| ![Network widget](assets/screenshots/widget-network.png) | ![Processor / RAM widget](assets/screenshots/widget-resources.png) |

| System information | |
|--------------------|-|
| ![System information widget](assets/screenshots/widget-sysinfo.png) | |

---

## Theme manager

The theming dialogue (click the wallpaper glyph): wallpaper picker, pywal
palette, rofi variants, bar themes, matuwall, lock screen, icons, and SDDM & GRUB.

![Theme manager](assets/screenshots/theme-manager.png)

---

## Settings

The floating settings window — nine pages in the sidebar, all applied live.

### Bar

Geometry, position, gaps and opacity.

![Settings — Bar](assets/screenshots/settings.png)

### Fonts

Text family and size, plus the module and quick-link icon sizes.

![Settings — Fonts](assets/screenshots/settings-fonts.png)

### Themes

Theme source (pywal / imported / manual), imported theme picker and manual
colours.

![Settings — Themes](assets/screenshots/settings-themes.png)

### Animations

The pill border animation, its mode and speed.

![Settings — Animations](assets/screenshots/settings-animations.png)

### Arc Menu

The FAB overlay's own four tabs: general geometry, theming source, colours and
the item list.

| General | Source |
|---------|--------|
| ![Arc Menu — General](assets/screenshots/settings-arcmenu-general.png) | ![Arc Menu — Source](assets/screenshots/settings-arcmenu-source.png) |

| Colors | Menu Items |
|--------|------------|
| ![Arc Menu — Colors](assets/screenshots/settings-arcmenu-colors.png) | ![Arc Menu — Menu Items](assets/screenshots/settings-arcmenu-items.png) |

### Menu

The start menu: enabled, layout, position, alignment and gaps, with a
*Follow hyprtk-bar* anchor.

![Settings — Menu](assets/screenshots/settings-menu.png)

### Quicklinks

Show, hide and reorder the quick-link buttons, and set their icon size.

![Settings — Quicklinks](assets/screenshots/settings-quicklinks.png)

### Modules

Show/hide every module, assign it to left / center / right and reorder it
within its section.

![Settings — Modules](assets/screenshots/settings-modules.png)

### Widgets

The desktop widgets and one configuration tab per widget.

| Clock | Weather |
|-------|---------|
| ![Widgets — Clock](assets/screenshots/settings-widgets-clock.png) | ![Widgets — Weather](assets/screenshots/settings-widgets-weather.png) |

| Audio visualizer | Hard disks |
|------------------|-----------|
| ![Widgets — Audio visualizer](assets/screenshots/settings-widgets-visualizer.png) | ![Widgets — Hard disks](assets/screenshots/settings-widgets-disk.png) |

| Network | Processor / RAM |
|---------|-----------------|
| ![Widgets — Network](assets/screenshots/settings-widgets-network.png) | ![Widgets — Processor / RAM](assets/screenshots/settings-widgets-resources.png) |

| System information | |
|--------------------|-|
| ![Widgets — System information](assets/screenshots/settings-widgets-sysinfo.png) | |

---

## Notifications

A built-in `org.freedesktop.Notifications` daemon: floating toasts ...

![Notification toast](assets/screenshots/notification-toast.png)

... and a notification center with action buttons and "Clear all".

![Notification center](assets/screenshots/notification-center.png)

---

## Calendar

The clock's calendar popup, with the date shown on hover.

![Calendar](assets/screenshots/calendar.png)
