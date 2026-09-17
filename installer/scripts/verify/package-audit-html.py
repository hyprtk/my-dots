#!/usr/bin/env python3
"""Render package-audit.tsv (from package-audit.sh) into output.html.

For every distro family/variant it shows each package the installer asks for and
how it is obtained: from the distro repo, the AUR, an extra repo (COPR/PPA/
RPMFusion/Brave/non-free), a source build, or not available at all.

Usage: package-audit-html.py <audit.tsv> <output.html> [repo-root]
"""

from __future__ import annotations

import html
import sys
from datetime import datetime, timezone
from pathlib import Path

FAMILY_LABEL = {
    "pacman": "Arch Linux (pacman)",
    "apt": "Debian / Ubuntu (apt)",
    "dnf": "Fedora / RHEL (dnf)",
    "zypper": "openSUSE (zypper)",
    "xbps": "Void Linux (xbps)",
    "apk": "Alpine Linux (apk)",
    "emerge": "Gentoo (emerge, advisory)",
    "nix": "NixOS (nix, advisory)",
}

# family -> ordered variants (variant, human label)
FAMILY_VARIANTS = {
    "pacman": [("arch", "Arch")],
    "apt": [
        ("bookworm", "Debian 12"),
        ("trixie", "Debian 13"),
        ("noble", "Ubuntu 24.04"),
        ("resolute", "Ubuntu 26.04"),
        ("mint22", "Mint 22.3"),
    ],
    "dnf": [("fedora", "Fedora")],
    "zypper": [("suse", "Tumbleweed")],
    "xbps": [("void", "Void")],
    "apk": [("alpine", "Alpine")],
}

FAMILY_ORDER = ["pacman", "apt", "dnf", "zypper", "xbps", "apk"]

STATUS_META = {
    "repo": ("repo", "In distro repo", "s-repo"),
    "aur": ("aur", "AUR", "s-aur"),
    "extra": ("extra", "Extra repo", "s-extra"),
    "extra-add": ("extra-add", "Extra repo (installer adds)", "s-extra"),
    "extra-todo": ("extra-todo", "Extra repo (not wired up)", "s-todo"),
    "source": ("source", "Built from source", "s-source"),
    "unavailable": ("unavailable", "Not available", "s-missing"),
    "unexpected": ("unexpected", "Unexpected miss", "s-missing"),
    "error": ("error", "Audit error", "s-missing"),
}

# Extra-repo route annotations the allow-list shorthand cannot convey.
OVERRIDES = {
    # Ubuntu's archive ships an older Hyprland (<0.55, no Lua config); the
    # installer pins the cppiber/hyprland PPA even though the archive resolves.
    ("apt", "noble", "hyprland"): ("extra-add", "cppiber/hyprland PPA (archive Hyprland < 0.55)"),
    ("apt", "resolute", "hyprland"): ("extra-add", "cppiber/hyprland PPA (archive Hyprland < 0.55)"),
    ("apt", "mint22", "hyprland"): ("extra-add", "cppiber/hyprland PPA (archive Hyprland < 0.55)"),
    ("apt", "noble", "hyprpicker"): ("extra-add", "cppiber/hyprland PPA"),
    ("apt", "resolute", "hyprpicker"): ("extra-add", "cppiber/hyprland PPA"),
    ("apt", "mint22", "hyprpicker"): ("extra-add", "cppiber/hyprland PPA"),
    ("apt", "noble", "hyprsunset"): ("extra-add", "cppiber/hyprland PPA"),
    ("apt", "resolute", "hyprsunset"): ("extra-add", "cppiber/hyprland PPA"),
    ("apt", "mint22", "hyprsunset"): ("extra-add", "cppiber/hyprland PPA"),
    # Fedora Hyprland + friends come from the COPR the installer enables.
    ("dnf", "fedora", "hyprland"): ("extra-add", "lionheartp/Hyprland COPR"),
    ("dnf", "fedora", "hyprpicker"): ("extra-add", "lionheartp/Hyprland COPR"),
    ("dnf", "fedora", "hyprsunset"): ("extra-add", "lionheartp/Hyprland COPR"),
    ("dnf", "fedora", "nwg-look"): ("source", "srcapps-install.sh (go build) — COPR also carries it"),
    # Brave is wired up from Brave's own repo on all three RPM/apt families.
    ("dnf", "fedora", "brave-browser"): ("extra-add", "Brave RPM repo"),
    ("zypper", "suse", "brave-browser"): ("extra-add", "Brave RPM repo"),
    ("apt", "bookworm", "brave-browser"): ("extra-add", "Brave apt repo"),
    ("apt", "trixie", "brave-browser"): ("extra-add", "Brave apt repo"),
    ("apt", "noble", "brave-browser"): ("extra-add", "Brave apt repo"),
    ("apt", "resolute", "brave-browser"): ("extra-add", "Brave apt repo"),
    ("apt", "mint22", "brave-browser"): ("extra-add", "Brave apt repo"),
    # srcapps-install.sh now builds these where the archive lacks them.
    ("apk", "alpine", "cliphist"): ("source", "srcapps-install.sh (go build)"),
    ("apt", "bookworm", "cliphist"): ("source", "srcapps-install.sh (go build)"),
    ("apt", "bookworm", "eza"): ("source", "srcapps-install.sh (cargo)"),
    ("apk", "alpine", "ipp-usb"): ("source", "srcapps-install.sh (go build + udev rule)"),
    # Installer-side name fallbacks (handled, not a gap).
    ("apt", "bookworm", "freerdp3-x11"): ("repo", "installer requests freerdp2-x11 on Debian 12"),
    ("apt", "trixie", "policykit-1-gnome"): ("extra-add", "Debian 13 dropped it; installer installs mate-polkit"),
    ("apt", "noble", "nvidia-driver"): ("extra-add", "Ubuntu ships no meta; installer picks nvidia-driver-5xx"),
    ("apt", "resolute", "nvidia-driver"): ("extra-add", "Ubuntu ships no meta; installer picks nvidia-driver-5xx"),
    ("apt", "mint22", "nvidia-driver"): ("extra-add", "Ubuntu ships no meta; installer picks nvidia-driver-5xx"),
}


def load_allow(path: Path) -> dict[tuple[str, str], str]:
    out: dict[tuple[str, str], str] = {}
    if not path.is_file():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        body, _, reason = line.partition("#")
        parts = body.split()
        if len(parts) < 2:
            continue
        fam, name = parts[0], parts[1]
        out[(fam, name)] = reason.strip()
    return out


def allow_reason(allow: dict[tuple[str, str], str], family: str, variant: str, name: str) -> str:
    for key in ((f"{family}/{variant}", name), (family, name)):
        if key in allow:
            return allow[key]
    return ""


def classify(family: str, variant: str, name: str, status: str, allow: dict) -> tuple[str, str]:
    if (family, variant, name) in OVERRIDES:
        return OVERRIDES[(family, variant, name)]
    if status == "OK":
        return ("repo", "")
    if status == "AUR":
        return ("aur", "Installed by the AUR helper (yay/paru)")
    if status == "ERROR":
        return ("error", "container run failed")
    reason = allow_reason(allow, family, variant, name)
    if not reason:
        return ("unexpected", "no allow-listed reason — investigate")
    low = reason.lower()
    if "srcapps" in low or "upstream installer" in low or "from source" in low or "builds it" in low:
        return ("source", reason)
    if "rpmfusion" in low or "rpm fusion" in low or "non-free" in low or "nonfree" in low:
        return ("extra-todo", reason)
    if "ppa" in low or "copr" in low or "brave's own" in low or "added by" in low:
        return ("extra-add", reason)
    if "community" in low:
        return ("extra", reason)
    if "dropped" in low or "removed" in low or "not packaged" in low or "monolithic" in low:
        return ("unavailable", reason)
    return ("unavailable", reason)


def esc(s: str) -> str:
    return html.escape(s, quote=True)


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    tsv_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2])
    repo_root = Path(sys.argv[3]) if len(sys.argv) > 3 else tsv_path.parent
    allow_path = repo_root / "installer/scripts/verify/container-matrix.allow"

    allow = load_allow(allow_path)

    # data[family][variant][name] = status
    data: dict[str, dict[str, dict[str, str]]] = {}
    for line in tsv_path.read_text().splitlines():
        parts = line.split("\t")
        if len(parts) < 4:
            continue
        fam, variant, name, status = parts[0], parts[1], parts[2], parts[3]
        data.setdefault(fam, {}).setdefault(variant, {})[name] = status

    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    # ── summary counts ──────────────────────────────────────────────────────
    counts: dict[str, dict[str, int]] = {}
    for fam in FAMILY_ORDER:
        if fam not in data:
            continue
        c = counts.setdefault(fam, {})
        for variant, names in data[fam].items():
            for name, status in names.items():
                cat, _ = classify(fam, variant, name, status, allow)
                c[cat] = c.get(cat, 0) + 1

    # ── render ──────────────────────────────────────────────────────────────
    rows: list[str] = []
    rows.append("<!DOCTYPE html>")
    rows.append("<html lang='en'><head><meta charset='utf-8'>")
    rows.append("<meta name='viewport' content='width=device-width, initial-scale=1'>")
    rows.append("<title>hyprtk multi-distro package audit</title>")
    rows.append("<style>")
    rows.append(DEFAULT_CSS)
    rows.append("</style></head><body>")
    rows.append("<div class='wrap'>")
    rows.append("<header><h1>hyprtk multi-distro package audit</h1>")
    rows.append(f"<p class='sub'>Every package the installer requests, resolved against live "
                f"repository metadata in throwaway containers. Generated {esc(now)}.</p></header>")

    rows.append("<section class='legend'>")
    for key in ("repo", "aur", "extra-add", "extra-todo", "source", "unavailable", "unexpected"):
        _, label, cls = STATUS_META[key]
        rows.append(f"<span class='chip {cls}'>{esc(label)}</span>")
    rows.append("</section>")

    # summary table
    rows.append("<section><h2>Summary</h2><table class='summary'><thead><tr>")
    rows.append("<th>Distribution</th><th class='num'>Repo</th><th class='num'>AUR</th>"
                "<th class='num'>Extra (added)</th><th class='num'>Extra (TODO)</th>"
                "<th class='num'>Source</th><th class='num'>Unavailable</th><th class='num'>Unexpected</th>"
                "</tr></thead><tbody>")
    for fam in FAMILY_ORDER:
        if fam not in counts:
            continue
        c = counts[fam]
        rows.append("<tr>"
                    f"<td>{esc(FAMILY_LABEL.get(fam, fam))}</td>"
                    f"<td class='num'>{c.get('repo', 0)}</td>"
                    f"<td class='num'>{c.get('aur', 0)}</td>"
                    f"<td class='num'>{c.get('extra-add', 0) + c.get('extra', 0)}</td>"
                    f"<td class='num'>{c.get('extra-todo', 0)}</td>"
                    f"<td class='num'>{c.get('source', 0)}</td>"
                    f"<td class='num'>{c.get('unavailable', 0)}</td>"
                    f"<td class='num'>{c.get('unexpected', 0) + c.get('error', 0)}</td>"
                    "</tr>")
    rows.append("</tbody></table></section>")

    # per-family tables
    for fam in FAMILY_ORDER:
        if fam not in data:
            continue
        variants = [(v, lbl) for v, lbl in FAMILY_VARIANTS.get(fam, [])
                    if v in data[fam]] or [(v, v) for v in data[fam]]
        names = sorted({n for v, _ in variants for n in data[fam].get(v, {})})
        rows.append(f"<section><h2>{esc(FAMILY_LABEL.get(fam, fam))}</h2>")
        rows.append("<table class='matrix'><thead><tr><th>Package</th>")
        for _, lbl in variants:
            rows.append(f"<th>{esc(lbl)}</th>")
        rows.append("<th>Route / notes</th></tr></thead><tbody>")
        for name in names:
            rows.append("<tr>")
            rows.append(f"<td class='pkg'>{esc(name)}</td>")
            notes: set[str] = set()
            cats: set[str] = set()
            for v, _ in variants:
                status = data[fam].get(v, {}).get(name)
                if status is None:
                    rows.append("<td class='cell na'>·</td>")
                    continue
                cat, note = classify(fam, v, name, status, allow)
                cats.add(cat)
                if note:
                    notes.add(note)
                _, label, cls = STATUS_META.get(cat, ("", cat, ""))
                rows.append(f"<td class='cell {cls}' title='{esc(label + (': ' + note if note else ''))}'>{esc(label)}</td>")
            rows.append("<td class='notes'>" + esc("; ".join(sorted(notes))) + "</td>")
            rows.append("</tr>")
        rows.append("</tbody></table></section>")

    # non-package components
    rows.append("<section><h2>Components not from a distro repo</h2>")
    rows.append("<table class='matrix'><thead><tr><th>Component</th><th>How it is obtained</th></tr></thead><tbody>")
    for comp, how in COMPONENTS:
        rows.append(f"<tr><td class='pkg'>{esc(comp)}</td><td class='notes'>{esc(how)}</td></tr>")
    rows.append("</tbody></table></section>")

    # action list: unexpected + extra-todo + unavailable
    actions: list[tuple[str, str, str, str]] = []
    for fam in FAMILY_ORDER:
        if fam not in data:
            continue
        for variant, names in data[fam].items():
            for name, status in names.items():
                cat, note = classify(fam, variant, name, status, allow)
                if cat in ("unexpected", "error", "extra-todo", "unavailable"):
                    actions.append((fam, variant, name, cat, note))
    if actions:
        rows.append("<section><h2>Action list (no working route today)</h2>")
        rows.append("<table class='matrix'><thead><tr><th>Distro</th><th>Package</th><th>Status</th><th>Why</th></tr></thead><tbody>")
        for fam, variant, name, cat, note in sorted(actions):
            _, label, cls = STATUS_META.get(cat, ("", cat, ""))
            rows.append(f"<tr><td>{esc(fam)}/{esc(variant)}</td><td class='pkg'>{esc(name)}</td>"
                        f"<td class='cell {cls}'>{esc(label)}</td><td class='notes'>{esc(note)}</td></tr>")
        rows.append("</tbody></table></section>")

    rows.append("</div></body></html>")

    out_path.write_text("\n".join(rows) + "\n")
    print(f"wrote {out_path} ({out_path.stat().st_size} bytes)")
    return 0


COMPONENTS = [
    ("awww (wallpaper daemon)", "Arch: AUR (awww). Elsewhere: built from source by installer/scripts/awww-install.sh (cargo; needs Rust >= 1.89). Void/Alpine: native swww."),
    ("pywal16 (`wal`)", "Vendored inside hyprtk-bar (vendor/pywal16); exposed as ~/.local/bin/wal. No distro package needed."),
    ("gtk4-layer-shell", "Built from source (meson) by srcapps-install.sh where the native package is missing (Debian 12 / Ubuntu 24.04)."),
    ("swappy", "Built from source (meson) by srcapps-install.sh where unpackaged (Debian/Ubuntu/Alpine)."),
    ("nwg-look", "Built from source (go) by srcapps-install.sh on Debian/Ubuntu/Fedora/Alpine/Void."),
    ("starship", "Upstream binary installer (pinned v1.26.0) by srcapps-install.sh where unpackaged."),
    ("gum, oh-my-posh, papirus-folders", "Bundled binaries in installer/standalone/, symlinked into ~/.local/bin."),
    ("hyprtk-bar", "Python venv from installer/hyprtk-bar; deps from the distro (bar DEPS/EXTRAS)."),
    ("Papirus icon theme (root)", "Upstream installer fetched to a temp file and run with DESTDIR=/root/.local/share/icons."),
    ("hyprtk/fonts, hyprtk/wallpaper", "git clone into ~/.local/share/fonts and ~/Pictures/Wallpapers."),
    ("oh-my-zsh + plugins", "git clone (upstream installer) into ~/.oh-my-zsh."),
    ("SDDM Sugar-Candy theme", "git clone from framagit, then patched for Qt6 + installed to /usr/share/sddm/themes."),
    ("Matuwall", "git clone + python venv (pip install) into ~/.local/share/Matuwall."),
    ("macOS-style cursors (bibata)", "pacman: AUR. Other families: not currently wired (allow-list/manual)."),
]

DEFAULT_CSS = """
:root{--bg:#0f1017;--bg2:#16171f;--fg:#c9c9d1;--dim:#8b8b98;--purple:#c084fc;--cyan:#22d3ee;
--green:#34d399;--amber:#fbbf24;--red:#f87171;--blue:#60a5fa;--violet:#a78bfa}
*{box-sizing:border-box}
body{margin:0;background:linear-gradient(160deg,#0b0c12,#12131c 60%,#0e0f16);color:var(--fg);
font:14px/1.45 ui-sans-serif,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1180px;margin:0 auto;padding:32px 20px 80px}
header h1{margin:0 0 4px;font-size:26px;color:#fff;letter-spacing:.3px}
header h1:before{content:"";display:inline-block;width:10px;height:10px;border-radius:50%;
background:var(--purple);margin-right:10px;box-shadow:0 0 14px var(--purple)}
.sub{color:var(--dim);margin:0 0 8px}
h2{color:var(--cyan);font-size:17px;margin:34px 0 10px;border-bottom:1px solid #262838;padding-bottom:6px}
table{width:100%;border-collapse:collapse;background:rgba(255,255,255,.02);border-radius:10px;overflow:hidden}
th,td{padding:6px 10px;text-align:left;border-bottom:1px solid #22242f}
th{background:#1a1c26;color:#dfe0ea;font-weight:600;position:sticky;top:0}
td.num,th.num{text-align:center}
td.pkg{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;color:#e8e8f0;white-space:nowrap}
.cell{text-align:center;font-size:12px;font-weight:600;white-space:nowrap}
.notes{color:var(--dim);font-size:12px}
.na{color:#3a3d4d}
.legend{margin:14px 0 4px;display:flex;gap:8px;flex-wrap:wrap}
.chip{font-size:12px;padding:3px 10px;border-radius:999px;border:1px solid #2c2f3f;color:var(--fg)}
.s-repo{color:var(--green)} .s-aur{color:var(--blue)} .s-extra{color:var(--cyan)}
.s-todo{color:var(--amber)} .s-source{color:var(--violet)} .s-missing{color:var(--red)}
.chip.s-repo{border-color:#1f5c46} .chip.s-aur{border-color:#22396b} .chip.s-extra{border-color:#1a5566}
.chip.s-todo{border-color:#6b551c} .chip.s-source{border-color:#4a3a78} .chip.s-missing{border-color:#6b2b2b}
td.cell.s-repo{color:var(--green)} td.cell.s-aur{color:var(--blue)} td.cell.s-extra{color:var(--cyan)}
td.cell.s-todo{color:var(--amber)} td.cell.s-source{color:var(--violet)} td.cell.s-missing{color:var(--red)}
tr:hover td{background:rgba(192,132,252,.05)}
"""


if __name__ == "__main__":
    sys.exit(main())
