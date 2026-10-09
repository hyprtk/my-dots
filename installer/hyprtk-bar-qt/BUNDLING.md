# Bundling & vendoring

hyprtk-bar-qt is a self-contained vendored app: it vendors the pieces it needs
so a machine with Quickshell/Qt6 installed needs no extra downloads.

## What is bundled

| Item | Path | Installed to |
|------|------|--------------|
| pywal16 (`wal`) | `vendor/pywal16/` | `~/.local/share/hyprtk-bar-qt/vendor/pywal16` (+ a `wal` launcher in the venv, symlinked to `~/.local/bin/wal`) |
| Nerd Font | `assets/fonts/SymbolsNerdFont-Regular.ttf` | `~/.local/share/fonts/` |
| Bar themes | `themes/` | `~/.config/hyprtk-bar-qt/themes/` |
| Clock widget themes | `assets/widgets/clock/` | `~/.config/hyprtk-bar-qt/widget-themes/clock/` |
| Wallpapers | `Wallpapers/` | `~/Pictures/Wallpapers/` (no-clobber) |
| Scripts | `scripts/` | `~/.local/share/hyprtk-bar-qt/scripts/` |
| Default config | `config.json` | `~/.config/hyprtk-bar-qt/config.json` (fresh installs only) |

## pywal16

`vendor/pywal16/` is a verbatim copy of
[pywal16](https://github.com/eylles/pywal16) (fork `hyprtk/pywal16`,
`wal 3.8.15`). It is pure Python (stdlib only) and is run from the bar's venv
via `PYTHONPATH` — no `pip install`, no build, no network. See
`vendor/pywal16/VENDOR.md`. Do not edit the vendored tree; fixes belong in the
bar, not upstream copies.

## Re-vendoring into hyprtk-multi-distro / merged

The bar is vendored byte-identically:

```sh
git -C <hyprtk-bar-qt checkout> archive HEAD | tar -x -C <tree>/installer/hyprtk-bar-qt
```

(`rm -rf` the destination first so removed files do not linger.)
