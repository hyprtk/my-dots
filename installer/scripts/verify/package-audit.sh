#!/bin/bash
# ── Package audit (container-hosted, per-package) ───────────────────────────
# Sibling of container-matrix.sh. Where the matrix only reports the *misses*,
# this resolves every native name the installer hands to a package manager and
# prints one machine-readable, per-name result line:
#
#   <family>\t<variant>\t<name>\t<OK|AUR|MISS>\t<note>
#
# The allowlist (container-matrix.allow) supplies the reason a MISS is expected
# (secondary repo, source build, manual); an unexpected MISS is flagged
# `unexpected`. `package-audit-html.py` turns the TSV into output.html.
#
# Usage:
#   package-audit.sh                # all installable families -> stdout TSV
#   package-audit.sh --family dnf   # one family (repeatable)
#   package-audit.sh --no-bar       # skip the vendored bar's DEPS/EXTRAS
#
# Progress goes to stderr; stdout is the TSV.
# ─────────────────────────────────────────────────────────────────────────────
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ALLOW_FILE="$ROOT/installer/scripts/verify/container-matrix.allow"
PODMAN="${PODMAN:-podman}"
AUDIT_TIMEOUT="${AUDIT_TIMEOUT:-1800}"

INSTALL_FAMILIES=(pacman apt dnf zypper xbps apk)
WITH_BAR=1
SEL_FAMILIES=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --family) SEL_FAMILIES+=("$2"); shift 2 ;;
        --no-bar) WITH_BAR=0; shift ;;
        -h|--help) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "package-audit: unknown argument: $1" >&2; exit 2 ;;
    esac
done

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

_script_names() {
    local pm="$1" s out=""
    for s in "$ROOT"/hypr/packages/*.sh; do
        grep -q -- '--list' "$s" || continue
        # manual_package_installs.sh is an opt-in helper, not part of
        # 1-install.sh; it must never contribute to the installer surface.
        case "$(basename "$s")" in manual_package_installs.sh) continue ;; esac
        out+=" $(HYPRTK_PM="$pm" timeout 15 bash "$s" --list 2>/dev/null)"
    done
    printf '%s' "$out"
}

_bar_names() {
    local pm="$1" f="$ROOT/installer/hyprtk-bar/install.sh"
    [ -f "$f" ] || return 0
    grep -oE "^(DEPS|EXTRAS)\[$pm\]=\"[^\"]*\"" "$f" | sed 's/.*="//; s/"$//'
}

_family_names() {
    local pm="$1"
    { _script_names "$pm"; [ "$WITH_BAR" -eq 1 ] && _bar_names "$pm"; } \
        | tr ' ' '\n' | sed '/^$/d' | sort -u
}

_aur_names() {
    [ "$#" -gt 0 ] || return 0
    local args=() n resp
    for n in "$@"; do args+=(--data-urlencode "arg[]=$n"); done
    resp=$(curl -sS -m 25 "${args[@]}" https://aur.archlinux.org/rpc/v5/info 2>/dev/null)
    printf '%s' "$resp" | jq -r '.results[]?.Name' 2>/dev/null
}

command -v "$PODMAN" >/dev/null 2>&1 || {
    echo "package-audit: '$PODMAN' not found — install podman" >&2; exit 2; }

families=("${INSTALL_FAMILIES[@]}")
[ "${#SEL_FAMILIES[@]}" -gt 0 ] && families=("${SEL_FAMILIES[@]}")

for pm in "${families[@]}"; do
    mapfile -t names < <(_family_names "$pm")
    [ "${#names[@]}" -eq 0 ] && continue
    resolver="$(_family_resolver "$pm")"
    [ -n "$resolver" ] || continue

    while read -r variant image; do
        [ -n "$variant" ] || continue
        echo "audit: $pm/$variant (${#names[@]} names)" >&2
        report=$(printf '%s\n' "${names[@]}" \
            | timeout "$AUDIT_TIMEOUT" "$PODMAN" run --rm -i "$image" sh -c "$resolver" 2>/dev/null)
        if [ -z "$report" ]; then
            echo "audit: container run failed for $pm/$variant" >&2
            while IFS= read -r n; do printf '%s\t%s\t%s\tERROR\tcontainer run failed\n' "$pm" "$variant" "$n"; done < <(printf '%s\n' "${names[@]}")
            continue
        fi

        miss=()
        while read -r st name; do
            [ -n "$name" ] || continue
            if [ "$st" = OK ]; then
                printf '%s\t%s\t%s\tOK\t\n' "$pm" "$variant" "$name"
            else
                miss+=("$name")
            fi
        done <<<"$report"

        declare -A aur=()
        if [ "$pm" = pacman ] && [ "${#miss[@]}" -gt 0 ]; then
            while read -r n; do [ -n "$n" ] && aur["$n"]=1; done < <(_aur_names "${miss[@]}")
        fi
        for name in "${miss[@]}"; do
            if [ -n "${aur[$name]:-}" ]; then
                printf '%s\t%s\t%s\tAUR\tAUR package (installed by the AUR helper)\n' "$pm" "$variant" "$name"
            else
                printf '%s\t%s\t%s\tMISS\t\n' "$pm" "$variant" "$name"
            fi
        done
    done < <(_family_rows "$pm")
done
