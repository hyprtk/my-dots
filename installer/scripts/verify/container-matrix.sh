#!/bin/bash
# ── T1: package-name resolution matrix (container-hosted) ───────────────────
# The authoritative cross-distro check for every native package name the
# installer hands to a package manager. For each package-manager family the
# installer supports it:
#
#   1. collects the native names from hypr/packages/*.sh (via their `--list`
#      handler) and, optionally, the vendored bar's DEPS/EXTRAS,
#   2. runs a throwaway container of that family (for apt, Debian 12/13 and
#      Ubuntu 24.04/26.04 — their package sets differ),
#   3. resolves every name against the live repository metadata *without*
#      installing anything (simulate / dry-run / repoquery),
#   4. reports OK / AUR / MISSING, with an allowlist for known-acceptable gaps.
#
# Arch names are checked against the official sync repos; a name absent there
# but present in the AUR is reported `AUR` (expected, not a failure). pacman
# package groups (e.g. xfce4) count as resolvable. Gentoo (emerge) and NixOS
# (nix) are advisory: 1-install.sh only prints their names, so they are listed
# but not resolved.
#
# Runs rootless podman — no VM, no root. This host has no overlayfs, so rootless
# podman uses the vfs driver selected by
# ~/.config/containers/storage.conf.d/00-vfs.conf.
#
# Usage:
#   container-matrix.sh                    # all installable families
#   container-matrix.sh --family apk ...   # only the named family(s)
#   container-matrix.sh --all              # also list emerge/nix (advisory)
#   container-matrix.sh --no-bar           # skip the vendored bar's lists
#   container-matrix.sh --list             # print names, run no containers
#
# Exit status: 0 when no unexpected package name is missing, 1 otherwise.
# ─────────────────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ALLOW_FILE="$ROOT/installer/scripts/verify/container-matrix.allow"
PODMAN="${PODMAN:-podman}"
MATRIX_TIMEOUT="${MATRIX_TIMEOUT:-1800}"

INSTALL_FAMILIES=(pacman apt dnf zypper xbps apk)
ADVISORY_FAMILIES=(emerge nix)

WITH_BAR=1
LIST_ONLY=0
INCLUDE_ADVISORY=0
SEL_FAMILIES=()

usage() { sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; }

while [ "$#" -gt 0 ]; do
    case "$1" in
        --family)  SEL_FAMILIES+=("$2"); shift 2 ;;
        --no-bar)  WITH_BAR=0; shift ;;
        --list)    LIST_ONLY=1; shift ;;
        --all)     INCLUDE_ADVISORY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "container-matrix: unknown argument: $1" >&2; exit 2 ;;
    esac
done

# ── Family metadata ─────────────────────────────────────────────────────────
_family_label() {
    case "$1" in
        pacman) echo "arch" ;;
        apt)    echo "debian" ;;
        dnf)    echo "fedora" ;;
        zypper) echo "suse" ;;
        xbps)   echo "void" ;;
        apk)    echo "alpine" ;;
        emerge) echo "gentoo" ;;
        nix)    echo "nixos" ;;
    esac
}

_family_coverage() {
    case "$1" in
        pacman) echo "all 11 Arch-family distros (shared pacman)" ;;
        apt)    echo "Debian/Ubuntu/Mint/Pop/Kali/Raspbian/..." ;;
        dnf)    echo "Fedora/RHEL/CentOS/Rocky/Alma/Oracle/Amazon" ;;
        zypper) echo "openSUSE/SLES" ;;
        xbps)   echo "Void" ;;
        apk)    echo "Alpine" ;;
        emerge) echo "Gentoo (advisory)" ;;
        nix)    echo "NixOS (advisory)" ;;
    esac
}

# One or more `<variant> <image>` rows per family. apt gets two: the package
# sets of Debian stable and Ubuntu differ materially.
_family_rows() {
    case "$1" in
        pacman) printf '%s %s\n' arch     docker.io/library/archlinux:latest ;;
        apt)    printf '%s %s\n' bookworm docker.io/library/debian:bookworm
                printf '%s %s\n' trixie   docker.io/library/debian:trixie
                printf '%s %s\n' noble    docker.io/library/ubuntu:24.04
                printf '%s %s\n' resolute docker.io/library/ubuntu:26.04
                printf '%s %s\n' mint22   docker.io/linuxmintd/mint22.3-amd64 ;;
        dnf)    printf '%s %s\n' fedora   registry.fedoraproject.org/fedora:latest ;;
        zypper) printf '%s %s\n' suse     registry.opensuse.org/opensuse/tumbleweed:latest ;;
        xbps)   printf '%s %s\n' void     docker.io/voidlinux/voidlinux:latest ;;
        apk)    printf '%s %s\n' alpine   docker.io/library/alpine:latest ;;
        emerge) printf '%s %s\n' gentoo   docker.io/gentoo/stage3:latest ;;
        nix)    printf '%s %s\n' nixos    docker.io/nixos/nix:latest ;;
    esac
}

# Resolver run inside the container: read names on stdin, print `OK|MISS <name>`.
_family_resolver() {
    case "$1" in
        pacman) cat <<'EOS'
pacman -Sy --noconfirm >/dev/null 2>&1
while IFS= read -r p; do
    [ -n "$p" ] || continue
    if pacman -Si "$p" >/dev/null 2>&1 || pacman -Sg "$p" >/dev/null 2>&1; then
        echo "OK $p"
    else
        echo "MISS $p"
    fi
done
EOS
        ;;
        apt) cat <<'EOS'
apt-get update -qq >/dev/null 2>&1
while IFS= read -r p; do
    [ -n "$p" ] || continue
    apt-get install -s -y "$p" >/dev/null 2>&1 && echo "OK $p" || echo "MISS $p"
done
EOS
        ;;
        dnf) cat <<'EOS'
dnf -q makecache >/dev/null 2>&1
while IFS= read -r p; do
    [ -n "$p" ] || continue
    got=$(dnf -q repoquery --available --qf '%{name}' "$p" 2>/dev/null | sort -u)
    if printf '%s\n' "$got" | grep -qxF "$p"; then echo "OK $p"; else echo "MISS $p"; fi
done
EOS
        ;;
        zypper) cat <<'EOS'
zypper --non-interactive --gpg-auto-import-keys refresh >/dev/null 2>&1
while IFS= read -r p; do
    [ -n "$p" ] || continue
    zypper --non-interactive install --dry-run "$p" >/dev/null 2>&1 \
        && echo "OK $p" || echo "MISS $p"
done
EOS
        ;;
        xbps) cat <<'EOS'
printf 'repository=https://repo-default.voidlinux.org/current\n' >/etc/xbps.d/00-repo.conf
xbps-install -S >/dev/null 2>&1
while IFS= read -r p; do
    [ -n "$p" ] || continue
    xbps-query -R -p pkgver "$p" >/dev/null 2>&1 && echo "OK $p" || echo "MISS $p"
done
EOS
        ;;
        apk) cat <<'EOS'
apk update >/dev/null 2>&1
while IFS= read -r p; do
    [ -n "$p" ] || continue
    apk search -e "$p" >/dev/null 2>&1 && echo "OK $p" || echo "MISS $p"
done
EOS
        ;;
    esac
}

# ── Name collection ─────────────────────────────────────────────────────────
_script_names() {  # hypr/packages/*.sh names for a family (--list honours HYPRTK_PM)
    local pm="$1" s out=""
    for s in "$ROOT"/hypr/packages/*.sh; do
        grep -q -- '--list' "$s" || continue
        out+=" $(HYPRTK_PM="$pm" timeout 15 bash "$s" --list 2>/dev/null)"
    done
    printf '%s' "$out"
}

_bar_names() {  # vendored bar native names (DEPS[<pm>] + EXTRAS[<pm>])
    local pm="$1" f="$ROOT/installer/hyprtk-bar/install.sh"
    [ -f "$f" ] || return 0
    grep -oE "^(DEPS|EXTRAS)\[$pm\]=\"[^\"]*\"" "$f" | sed 's/.*="//; s/"$//'
}

_family_names() {  # one name per line, sorted unique
    local pm="$1"
    { _script_names "$pm"; [ "$WITH_BAR" -eq 1 ] && _bar_names "$pm"; } \
        | tr ' ' '\n' | sed '/^$/d' | sort -u
}

# ── Allowlist ───────────────────────────────────────────────────────────────
# Lines: `<family>[/<variant>] <name> # reason`. A bare family matches any of
# its variants; `family/variant` matches only that one.
declare -A ALLOWED=()
_load_allowlist() {
    [ -f "$ALLOW_FILE" ] || return 0
    local fam name _reason
    while read -r fam name _reason; do
        case "$fam" in ''|'#'*) continue ;; esac
        ALLOWED["$fam:$name"]=1
    done < "$ALLOW_FILE"
}
_is_allowed() {  # family variant name
    [ -n "${ALLOWED[$1/$2:$3]:-}${ALLOWED[$1:$3]:-}" ]
}

# ── AUR resolution (pacman misses only) ─────────────────────────────────────
_aur_names() {  # args: names; prints those present in the AUR
    [ "$#" -gt 0 ] || return 0
    local args=() n resp
    for n in "$@"; do args+=(--data-urlencode "arg[]=$n"); done
    resp=$(curl -sS -m 25 "${args[@]}" https://aur.archlinux.org/rpc/v5/info 2>/dev/null)
    printf '%s' "$resp" | jq -r '.results[]?.Name' 2>/dev/null
}

# ── Main ────────────────────────────────────────────────────────────────────
_load_allowlist

families=("${INSTALL_FAMILIES[@]}")
[ "$INCLUDE_ADVISORY" -eq 1 ] && families+=("${ADVISORY_FAMILIES[@]}")
[ "${#SEL_FAMILIES[@]}" -gt 0 ] && families=("${SEL_FAMILIES[@]}")

if [ "$LIST_ONLY" -eq 1 ]; then
    for pm in "${families[@]}"; do
        echo "===== $pm ($(_family_coverage "$pm"))"
        _family_names "$pm"
    done
    exit 0
fi

command -v "$PODMAN" >/dev/null 2>&1 || {
    echo "container-matrix: '$PODMAN' not found — install podman" >&2; exit 2; }

TOTAL_OK=0; TOTAL_AUR=0; TOTAL_ALLOWED=0; TOTAL_MISS=0; TOTAL_ERR=0

for pm in "${families[@]}"; do
    echo "====================================================================="
    echo "  $(_family_label "$pm")  ($pm) — $(_family_coverage "$pm")"
    echo "====================================================================="

    mapfile -t names < <(_family_names "$pm")
    if [ "${#names[@]}" -eq 0 ]; then
        echo "  (no resolvable names — advisory/manual only)"; echo ""; continue
    fi
    resolver="$(_family_resolver "$pm")"
    if [ -z "$resolver" ]; then
        echo "  advisory only (${#names[@]} names):"
        printf '    %s\n' "${names[@]}"; echo ""; continue
    fi

    while read -r variant image; do
        [ -n "$variant" ] || continue
        echo "  -- $variant  ($image)"
        report=$(printf '%s\n' "${names[@]}" \
            | timeout "$MATRIX_TIMEOUT" "$PODMAN" run --rm -i "$image" sh -c "$resolver" 2>/dev/null)
        rc=$?
        if [ "$rc" -ne 0 ] || [ -z "$report" ]; then
            echo "     ERROR: container run failed (rc=$rc)"
            TOTAL_ERR=$((TOTAL_ERR + 1)); continue
        fi

        ok=0; miss=()
        while read -r st name; do
            case "$st" in
                OK) ok=$((ok + 1)) ;;
                MISS) miss+=("$name") ;;
            esac
        done <<<"$report"

        declare -A aur=()
        if [ "$pm" = pacman ] && [ "${#miss[@]}" -gt 0 ]; then
            while read -r n; do [ -n "$n" ] && aur["$n"]=1; done < <(_aur_names "${miss[@]}")
        fi

        aur_n=0; allowed=0; unexpected=0
        for name in "${miss[@]}"; do
            if [ -n "${aur[$name]:-}" ]; then
                echo "     AUR   $name"; aur_n=$((aur_n + 1))
            elif _is_allowed "$pm" "$variant" "$name"; then
                echo "     allow $name"; allowed=$((allowed + 1))
            else
                echo "     MISS  $name"; unexpected=$((unexpected + 1))
            fi
        done
        echo "     -> $ok ok, $aur_n AUR, $allowed allowed, $unexpected unexpected"
        TOTAL_OK=$((TOTAL_OK + ok)); TOTAL_AUR=$((TOTAL_AUR + aur_n))
        TOTAL_ALLOWED=$((TOTAL_ALLOWED + allowed)); TOTAL_MISS=$((TOTAL_MISS + unexpected))
    done < <(_family_rows "$pm")
    echo ""
done

echo "====================================================================="
echo "  MATRIX: $TOTAL_OK resolvable, $TOTAL_AUR AUR, $TOTAL_ALLOWED allowed, $TOTAL_MISS unexpected"
if [ "$TOTAL_MISS" -ne 0 ] || [ "$TOTAL_ERR" -ne 0 ]; then
    echo "  RESULT: FAIL"
    [ "$TOTAL_MISS" -ne 0 ] && echo "  Fix the names above, or add them to:"
    [ "$TOTAL_MISS" -ne 0 ] && echo "    $ALLOW_FILE   (lines: '<family>[/<variant>] <name> # reason')"
    exit 1
fi
echo "  RESULT: PASS"
