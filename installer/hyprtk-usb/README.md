# hyprtk-usb (Python)

The Python implementation of **hyprtk-usb** — write a
[hyprtk](https://github.com/hyprtk/Hyprtk-ISO-Creator) ISO to a USB stick and,
optionally, add the **`hyprtk-persist`** partition the ISO's *Hyprtk live with
persistence* boot entry looks for.

It is a peer of the Go implementation (in `../cmd` and `../internal`) and shares
the same behaviour, guardrails and plan geometry. The UI uses
[`rich`](https://github.com/Textualize/rich) and carries the hyprtk look:
**double-border panels** with the **mauve (`#c084fc`) / cyan (`#22d3ee`)** palette
resolved from pywal, as inline prompts — no full-screen takeover.

## Install

```bash
cd python
python -m venv .venv && . .venv/bin/activate
pip install -e .

# or just run it in place
PYTHONPATH=. python -m hyprtk_usb
```

Requires Python 3.10+ and, at runtime, `dd`-equivalent Go I/O plus `sfdisk`,
`mkfs.ext4`, `blkid`, `lsblk` and `findmnt`.

## Usage

```bash
# interactive (TUI)
hyprtk-usb

# non-interactive
sudo hyprtk-usb --iso ~/Documents/Isos/hyprtk-*.iso --target /dev/sda
```

Same flags as the Go binary and the shell script: `--iso`, `--target`, `--size`
(`8G`/`512M`/`50%`/`rest`), `--no-persist`, `--refresh`, `--dry-run`, `-y/--yes`,
`--tui`, `--test`.

Writing needs root — the program re-execs itself under `sudo`.

## Layout

```
hyprtk_usb/core.py    ISO/device discovery, planning, guardrails, writer
hyprtk_usb/ui.py      rich theme + hyprtk-styled panels and prompts
hyprtk_usb/cli.py     argparse flags + TUI / non-interactive flows
tests/                unittest suite (+ an sfdisk integration test)
```

## Tests

```bash
cd python
PYTHONPATH=. python -m unittest discover -s tests -v
```
