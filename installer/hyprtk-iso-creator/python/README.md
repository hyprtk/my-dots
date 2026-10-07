# Hyprtk ISO Creator (GUI)

The GTK 4 front end for **Hyprtk-ISO-Creator** — a short wizard over
[`hyprtk-iso-builder.sh`](../hyprtk-iso-builder.sh). It collects the builder's
options, then runs the builder as root (via a `pkexec` helper) and shows its
**live output** as the ISO is assembled.

The GUI runs **unprivileged**: only the builder — which needs root for
`mkarchiso` — is elevated, by `hyprtk_isocreator.helper` launched through
`pkexec`, so the GTK app never runs as root.

## Install

```bash
# from the repo root
bash install.sh
```

This creates a venv (with system site-packages, so it finds PyGObject/GTK 4),
installs `python/` into it, links `hyprtk-iso-creator` / `hyprtk-iso-creator-helper`
into `~/.local/bin`, records the checkout path, and installs a desktop entry.

## Run

```bash
hyprtk-iso-creator
# or in place, from python/:
PYTHONPATH=. python -m hyprtk_isocreator
```

## Notes

- The app needs the **checkout** (not just the script) — the builder reads
  `airootfs/`, `packages.hyprtk` and `aur-packages.txt` from the repo root. The
  app finds it from `$HYPRTK_ISO_ROOT`, by walking up from the package, or from
  the copy of the builder that `install.sh` places under
  `~/.local/share/hyprtk-iso-creator/repo/` (recorded in `.../root`).
- Building requires **Arch Linux** (or an Arch-based host), network access during
  the build, and roughly 15 GB in `/tmp` plus 5-8 GB for the ISO.
- The wizard exposes every builder flag: source dir, ISO name/label, output dir,
  build root, `--no-aur`, `--no-matuwall`, `--profile-only`, `--keep-work`.
