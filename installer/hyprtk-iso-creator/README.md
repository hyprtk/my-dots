# Hyprtk-ISO-Creator

Build a **live Arch Linux ISO with the hyprtk desktop preinstalled and
preconfigured** — a pywal-themed Hyprland session with hyprtk-bar, ready to use
the moment it boots.

The builder starts from the stock archiso `releng` profile and adds:

- every package in [`packages.hyprtk`](packages.hyprtk), verified against your
  sync databases
- the AUR extras in [`aur-packages.txt`](aur-packages.txt), built on the host
  (best-effort, non-fatal)
- **matuwall** (the wallpaper picker), built from source on the host
- the hyprtk dotfiles vendored into `/etc/skel` — every new user gets a
  preconfigured `~/hyprtk` plus the `~/.config` symlinks
- **SDDM autologin** straight into Hyprland for the live user `hyprtk`

## Requirements

- Arch Linux (or an Arch-based host) with `sudo`
- Network access during the build (package download + `dbus-next` for the bar)
- Enough free space: roughly **15 GB** in `/tmp` and **5-8 GB** for the ISO
- For AUR extras: `base-devel` on the host, plus each package's makedepends

## Usage

```bash
git clone https://github.com/hyprtk/Hyprtk-ISO-Creator.git
cd Hyprtk-ISO-Creator
./hyprtk-iso-builder.sh
```

Run it as your normal user — the script re-execs itself with `sudo` because
`mkarchiso` needs root. When it finishes the ISO is written to your home
directory.

### Options

| Option | Meaning |
| --- | --- |
| `-y`, `--yes` | Skip the confirmation prompt |
| `--hyprtk-dir DIR` | hyprtk dotfiles source (default: `$HYPRTK_DIR`, `~/hyprtk`, else cloned from `hyprtk/dotfiles`) |
| `--iso-name NAME` | ISO file name (default `hyprtk`) |
| `--iso-label LABEL` | ISO label, max 32 chars (default `HYPRTK_<YYYYMM>`) |
| `--out-dir DIR` | Where the ISO is written (default: your home) |
| `--build-root DIR` | Scratch dir for the profile/work (default `/tmp/hyprtk-iso-build`) |
| `--no-aur` | Skip building the AUR extras |
| `--no-matuwall` | Skip building matuwall from source |
| `--profile-only` | Assemble the profile and stop (no ISO build) |
| `--keep-work` | Keep the assembled profile after the build |

`--profile-only --keep-work` is handy for inspecting what went onto the image
without waiting for a full `mkarchiso` run.

## GUI

There is a Qt (PySide6) front end (`python/`, launcher `hyprtk-iso-creator`) — a short
wizard over this same builder: choose the source, name/label and output
locations, toggle the extras, review, then watch the builder's **live output**
as the ISO is assembled. It runs unprivileged; only the builder (which needs
root for `mkarchiso`) is elevated, via a `pkexec` helper.

```bash
bash install.sh          # installs the GUI (venv + ~/.local/bin launchers + desktop entry)
hyprtk-iso-creator       # launch it
```

Because the builder reads `airootfs/`, `packages.hyprtk` and `aur-packages.txt`
relative to this repo, the GUI locates the **checkout** (`$HYPRTK_ISO_ROOT`, a
walk up from the package, or the copy of the builder that `install.sh` places
under `~/.local/share/hyprtk-iso-creator/repo/`). It is Arch-only, like the
builder.

## What the live ISO looks like

- **Live user:** `hyprtk` (password `hyprtk`, passwordless sudo)
- **Root:** password `toor` (console/tty login; SDDM hides uid 0)
- **Login:** SDDM autologins to the **hyprland** session — no greeter
- **Theming:** pywal palette is generated at build time from
  `assets/Wallpapers/default.png`, so the bar, rofi, lock screen and icons are
  already coloured on first boot
- **New users:** creating any account (e.g. from the live session) copies
  `/etc/skel`, so the new user's `~/hyprtk` and `~/.config` symlinks are set up;
  a one-shot systemd user unit (`hyprtk-first-run`) installs the bar and runs
  pywal on first login

## Install to disk

The live session carries an offline installer, **`hyprtk-deploy`** (also in the
bar's app menu as *Install hyprtk to disk*). It clones the running live system to
a disk — no network, no separate package set, installed == live:

- **Target:** GPT, single disk — 1 MiB `bios_grub` + 1 GiB FAT32 ESP + ext4 root
  + a 4 GiB swapfile (no LUKS)
- **Clone:** `rsync` the live root (keeps `/usr`, `/etc`, `/etc/skel`,
  `/var/lib/pacman`; drops volatile paths and `/home/*`)
- **Bootloader:** GRUB for both UEFI and BIOS
- **Identity:** prompts hostname/user/passwords/timezone/locale/keymap, creates
  the user, and strips the live-only account, autologin and passwordless sudo
- Refuses to target the live medium and requires the device name typed to confirm

It is a `gum` TUI; run it from the desktop entry or `sudo hyprtk-deploy` in a
terminal.

## Make a USB stick (optional persistence)

Use **[hyprtk-usb](https://github.com/hyprtk/hyprtk-usb)** — a separate Go app that
writes the ISO to a USB stick and, by default, adds the **`hyprtk-persist`**
partition the ISO's *Hyprtk live with persistence* boot entry looks for. The ISO
itself is unchanged and stays ephemeral by default.

```bash
# interactive TUI
hyprtk-usb

# or non-interactive
sudo hyprtk-usb --iso ~/Documents/Isos/hyprtk-*.iso --target /dev/sda
```

It `dd`s the ISO (iso-hybrid, MBR) with the stick's existing two MBR entries
(the iso9660 and the EFI FAT) preserved verbatim, then appends a 1 MiB-aligned
Linux partition in the free space and formats it `ext4 -L hyprtk-persist`. Boot
the stick and pick **Hyprtk live with persistence**; the default entry boots
ephemeral as before. See the
[hyprtk-usb README](https://github.com/hyprtk/hyprtk-usb#readme) for the flags
(`--no-persist`, `--size`, `--refresh`, `--dry-run`) and safety notes.

### Doing it by hand

```bash
ISO=~/Documents/Isos/hyprtk-*.iso
DEV=/dev/sdX                     # the whole stick, e.g. /dev/sda
dd if=$ISO of=$DEV bs=4M conv=fsync status=progress; sync
# start 1 MiB past the end of the ISO image; align to 2048 sectors
ISO_END=$(( ($(stat -c %s $ISO) + 511) / 512 ))
START=$(( (ISO_END + 2047) / 2048 * 2048 ))
END=$(( $(blockdev --getsz $DEV) - 1 ))
printf 'start=%s, size=%s, type=83\n' "$START" "$((END-START+1))" | sudo sfdisk --append "$DEV"
sudo partprobe $DEV
sudo mkfs.ext4 -L hyprtk-persist "${DEV}3"     # nvme/mmcblk use "${DEV}p3"
```

## How it fits together

```
hyprtk-iso-builder.sh      # the builder
packages.hyprtk            # official packages baked into the ISO
aur-packages.txt           # AUR extras, built on the host
install.sh                 # installs the optional Qt (PySide6) GUI
python/                    # the Qt (PySide6) front end (hyprtk_isocreator)
airootfs/                  # overlay merged onto the releng profile
  etc/sddm.conf.d/         # autologin + Wayland greeter
  etc/sudoers.d/           # live-user passwordless sudo
  usr/share/hyprtk-iso/    # staged: generated skel + os-release
  usr/local/bin/hyprtk-deploy      # offline live-to-disk installer
  usr/share/applications/hyprtk-deploy.desktop
  usr/local/bin/hyprtk-first-run   # per-user first-run setup
  root/customize_airootfs.sh       # installs the staged files, creates the live
                                   # user, installs bar/pywal, enables services
```

The builder copies `releng`, edits `profiledef.sh`, merges the package lists,
generates the skel tree from your hyprtk checkout (trimming `assets/screenshots`,
`distro/` and the root caches), then runs `mkarchiso`.

`/etc/skel` and `/usr/lib/os-release` are staged under `usr/share/hyprtk-iso/`
rather than shipped directly in the overlay: archiso copies `airootfs` into the
new root *before* pacstrap, so a path that a package also owns (`grml-zsh-config`
ships `/etc/skel/.zshrc`, `filesystem` ships `/usr/lib/os-release`) would be a
file conflict. `customize_airootfs.sh` installs them after the packages, then
deletes the staging dir.

## AUR extras

`aur-packages.txt` is built with `makepkg --nodeps --skippgpcheck` as your
normal user, then installed into the chroot by `customize_airootfs.sh`. The
stage is **best-effort**: anything that fails to build is reported and skipped,
and the ISO is still produced. Because of `--nodeps`, the host must already
have each package's build dependencies (`--skippgpcheck` skips source PGP
verification; checksums are still enforced). The visually important extras
(`swaylock-effects`, `bibata-cursor-theme`, `sddm-theme-sugar-candy-git`) are
listed out of the box; if they are missing the ISO falls back gracefully
(plain `swaylock` config, default cursor/SDDM theme). The default screen
locker/idle daemon are `hyprlock`/`hypridle` from the official repos.

Disable the stage with `--no-aur` if you want a fully reproducible build from
the official repos only.

## Notes

- The live root filesystem is writable through archiso's RAM overlay, so the
  bar's venv and the generated `~/.cache/wal` live in memory and vanish on
  reboot — exactly what you want for a live session.
- The AUR build runs on the **host** and (with `--nodeps`) does not install
  anything to it; build logs are kept under
  `~/.cache/hyprtk-iso/aur/<pkg>.log`.
- `--profile-only` also accepts `ARCHISO_RELENG=/path/to/releng` to use a
  different base profile.
