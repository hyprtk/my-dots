# Vendored: pywal16

This directory is a **verbatim copy** of the pywal16 source tree, vendored into
hyprtk-bar so the bar (and the merged `1-install.sh`) no longer depend on a
separate system/AUR install of `python-pywal16-git`.

## Provenance

| Field | Value |
|-------|-------|
| Upstream | https://github.com/eylles/pywal16 |
| Fork (source of the copy) | https://github.com/hyprtk/pywal16 |
| Version | `3.8.15` (tag) |
| Pinned commit | `a04c3e3b57ec57bdf080a863f45f917a18208e58` (`a04c3e3`) |
| Commit date | 2026-04-10 |
| License | MIT — see `LICENSE.md` |
| Vendored on | 2026-09-14 |

## What is included

- `pywal/` — the package (`__main__.py` provides the `wal` CLI entry point)
- `data/man/man1/wal.1` — man page (kept for upstream `setup.py`)
- `setup.py`, `MANIFEST.in` — kept so the tree remains pip-installable
- `README.md`, `CHANGELOG.md`, `LICENSE.md` — upstream docs + license

## What is excluded

Dev/meta only, none of it needed at runtime: `.git/`, `.github/`, `tests/`,
`.travis.yml`, `.pylintrc`, `.gitignore`, `FUNDING.yml`, `__pycache__/`,
`*.pyc`.

## How it is consumed

No `pip install`, no PyPI, no build step. `install.sh` copies this directory to
`~/.local/share/hyprtk-bar/vendor/pywal16/` and drops a `wal` launcher that puts
the tree on `PYTHONPATH` and runs the bar's venv Python:

```bash
export PYTHONPATH="$INSTALL_DIR/vendor/pywal16${PYTHONPATH:+:$PYTHONPATH}"
exec "$INSTALL_DIR/venv/bin/python3" -m pywal "$@"
```

The default `wal` backend is pure Python (stdlib only); Pillow is imported only
by the optional image export path in `export.py`.

## Do not edit

Everything here is upstream code. Local fixes belong in hyprtk-bar, not in the
vendored tree — otherwise the next update clobbers them.

## Updating

```bash
# from the fork checkout
cd ~/Documents/GitHub/pywal16
git fetch && git checkout <tag-or-commit>

# re-sync into the bar (same excludes as the original vendor)
rsync -a \
  --exclude '.git/' --exclude '.github/' --exclude 'tests/' \
  --exclude '.travis.yml' --exclude '.pylintrc' --exclude '.gitignore' \
  --exclude 'FUNDING.yml' --exclude '__pycache__/' --exclude '*.pyc' \
  ./ ~/Projects/AI-Projects/hyprtk-bar/vendor/pywal16/
```

Then update the version/commit/date in the table above and re-run the bar's
self-test (`wal -v`).
