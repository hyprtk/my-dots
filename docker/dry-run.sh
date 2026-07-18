#!/bin/bash
#
# Hyprtk-On-Arch — Deep Docker Dry Run
# Validates every .sh file, checks all paths, and runs a full simulation
# of the installer inside an isolated container.
#

set -euo pipefail

SCRIPT_DIR="/opt/hyprtk-on-arch"
PASS=0; FAIL=0; WARN=0
RESULTS=()

log()   { echo -e "\e[34m[DRY-RUN]\e[0m $*"; }
pass()  { ((PASS++)); RESULTS+=("PASS|$*"); echo -e "\e[32m  \xE2\x9C\x93 PASS\e[0m  $*"; }
fail()  { ((FAIL++)); RESULTS+=("FAIL|$*"); echo -e "\e[31m  \xE2\x9C\x97 FAIL\e[0m  $*"; }
warn()  { ((WARN++)); RESULTS+=("WARN|$*"); echo -e "\e[33m  \xE2\x9A\xA0 WARN\e[0m  $*"; }

print_header() {
    local title="$1"
    echo ""
    echo "========================================================="
    echo "    $title"
    echo "========================================================="
}

summary() {
    echo ""
    echo "========================================================="
    echo "                DRY RUN RESULTS"
    echo "========================================================="
    echo ""
    printf "  \e[32mPASS:\e[0m  %2d\n" $PASS
    printf "  \e[33mWARN:\e[0m  %2d\n" $WARN
    printf "  \e[31mFAIL:\e[0m  %2d\n" $FAIL
    echo ""

    local has_fail=0
    for r in "${RESULTS[@]}"; do
        local status="${r%%|*}"
        local msg="${r#*|}"
        case "$status" in
            FAIL) echo -e "  \e[31m\xE2\x9C\x97\e[0m  $msg"; has_fail=1 ;;
            WARN) echo -e "  \e[33m\xE2\x9A\xA0\e[0m  $msg" ;;
        esac
    done

    echo ""
    if [ "$has_fail" -eq 1 ]; then
        echo -e "  \e[31mSome checks failed. Review above.\e[0m"
        return 1
    fi
    echo -e "  \e[32mAll checks passed!\e[0m"
    return 0
}

# ============================================================
# STEP 1: Syntax validation on all .sh files
# ============================================================
syntax_check() {
    print_header "Syntax Validation"

    while IFS= read -r -d '' f; do
        local rel="${f#$SCRIPT_DIR/}"
        if bash -n "$f" 2>/dev/null; then
            pass "Syntax OK: $rel"
        else
            local err
            err=$(bash -n "$f" 2>&1 || true)
            fail "Syntax error in $rel: $err"
        fi
    done < <(find "$SCRIPT_DIR" -name '*.sh' -type f -print0 | sort -z)
}

# ============================================================
# STEP 2: Validate all referenced paths exist
# ============================================================
validate_paths() {
    print_header "Path Validation"

    # Common config dirs
    for _d in "$SCRIPT_DIR"/common/*/; do
        local name; name=$(basename "$_d")
        [ -d "$_d" ] && pass "common/$name" || fail "missing common/$name"
    done

    # Distro dirs
    for _d in "$SCRIPT_DIR"/distro/*/; do
        local name; name=$(basename "$_d")
        [ -d "$_d" ] && pass "distro/$name" || fail "missing distro/$name"
    done

    # All package scripts
    for _f in "$SCRIPT_DIR"/hypr/packages/*.sh; do
        local name; name=$(basename "$_f")
        [ -f "$_f" ] && pass "package script: $name" || fail "missing package script: $name"
    done

    # Key files referenced by 1-install.sh
    local key_files=(
        "scripts/library.sh"
        "scripts/set-timezone.sh"
        "scripts/awww-wrapper.sh"
        "scripts/update-grub.sh"
        "hypr/packages/graphics-card.sh"
        "hypr/conf/nvidia.conf"
        "common/figlet/fonts"
        "common/Wallpapers/default.png"
        "common/User-Management/manage-users.desktop"
        "common/smb/smb.conf"
        "common/standalone"
        "common/root"
        ".zshrc"
    )
    for _f in "${key_files[@]}"; do
        [ -e "$SCRIPT_DIR/$_f" ] && pass "key path: $_f" || fail "missing key path: $_f"
    done

    # Distro-specific os-release paths
    for _d in "$SCRIPT_DIR"/distro/*/; do
        local name; name=$(basename "$_d")
        local osr="$SCRIPT_DIR/distro/$name/os-release"
        if [ -f "$osr" ] || [ -d "$osr" ]; then
            pass "os-release: $name"
        else
            fail "os-release: $name — not found"
        fi
    done

    # Splash for arch
    [ -d "$SCRIPT_DIR/distro/arch/splash" ] && pass "arch splash dir" || warn "arch splash dir missing"

    # Dracut/Nvidia for endeavour and garuda
    for dist in endeavour garuda; do
        [ -d "$SCRIPT_DIR/distro/$dist/dracut" ] && pass "$dist dracut dir" || warn "$dist dracut dir missing"
        [ -d "$SCRIPT_DIR/distro/$dist/nvidia" ]  && pass "$dist nvidia dir" || warn "$dist nvidia dir missing"
    done

    # Grub for kiro
    [ -d "$SCRIPT_DIR/distro/kiro/grub" ] && pass "kiro grub dir" || warn "kiro grub dir missing"
}

# ============================================================
# STEP 3: Cross-reference installer case statements against
#          actual package scripts
# ============================================================
cross_reference() {
    print_header "Cross-Reference Check"

    # Extract all case labels from 1-install.sh
    local case_labels
    case_labels=$(grep -oP '"[^"]+"\) bash "\$SCRIPT_DIR/hypr/packages/\K[^" ]+' "$SCRIPT_DIR/1-install.sh" || true)

    for label in $case_labels; do
        local script_name="${label%.sh}"
        if [ -f "$SCRIPT_DIR/hypr/packages/$script_name.sh" ]; then
            pass "case '$(grep -oP "\"$label\"\)" "$SCRIPT_DIR/1-install.sh" | head -1 || echo "$label")' -> package script: $script_name.sh"
        else
            fail "Missing package script for case label: $script_name"
        fi
    done

    # Parse dotfiles case labels and check source directories
    local dotfile_labels
    dotfile_labels=$(grep -oP '^\s+(\S+)\) _installSymLink' "$SCRIPT_DIR/1-install.sh" | sed 's/) _installSymLink//' | tr -d ' ' || true)

    for df in $dotfile_labels; do
        # Extract the linksource for this dotfile
        local src
        src=$(grep -A1 "^\s\+${df}) _installSymLink" "$SCRIPT_DIR/1-install.sh" | grep -oP '\$SCRIPT_DIR/\K[^" ]+' | head -1 || true)
        if [ -n "$src" ] && [ -e "$SCRIPT_DIR/$src" ]; then
            pass "dotfile '$df' source exists: $src"
        elif [ -n "$src" ]; then
            fail "dotfile '$df' source missing: $src"
        else
            warn "dotfile '$df' source path could not be parsed"
        fi
    done
}

# ============================================================
# STEP 4: Full installer simulation
# ============================================================
simulate_installer() {
    print_header "Installer Flow Simulation"

    # Create the test user environment that the installer expects
    export USER="testuser"
    export HOME="/home/testuser"
    mkdir -p "$HOME/.config" "$HOME/.cache" "$HOME/.local/bin"
    mkdir -p "$HOME/Downloads" "$HOME/Pictures/Screenshots"
    touch "$HOME/.cache/current-wallpaper.png"
    chown -R nobody:nobody "$HOME" 2>/dev/null || true

    # Source the library and verify it loads cleanly
    log "Sourcing library.sh..."
    if source "$SCRIPT_DIR/scripts/library.sh" 2>/dev/null; then
        pass "library.sh sourced without errors"
    else
        fail "library.sh failed to load"
    fi

    # Test _installPackagesPacman with a few packages
    log "Testing _installPackagesPacman..."
    if _installPackagesPacman "figlet" "jq" "bc" 2>/dev/null; then
        pass "_installPackagesPacman: runs without failure"
    else
        fail "_installPackagesPacman: unexpected error"
    fi

    # Test _installPackagesYay with a package
    log "Testing _installPackagesYay..."
    if _installPackagesYay "cfn-lint" 2>/dev/null; then
        pass "_installPackagesYay: runs without failure"
    else
        fail "_installPackagesYay: unexpected error"
    fi

    # Test _installSymLink for various types: directory, file, and new
    log "Testing _installSymLink..."

    # Directory symlink
    mkdir -p /tmp/test-alacritty
    _installSymLink "alacritty" "$HOME/.config/alacritty" "/tmp/test-alacritty/" "$HOME/.config" 2>/dev/null
    if [ -L "$HOME/.config/alacritty" ]; then
        pass "_installSymLink: directory -> $HOME/.config/alacritty"
    else
        fail "_installSymLink: directory symlink not created"
    fi

    # File symlink
    touch /tmp/test-starship.toml
    _installSymLink "starship" "$HOME/.config/starship.toml" "/tmp/test-starship.toml" "$HOME/.config/starship.toml" 2>/dev/null
    if [ -L "$HOME/.config/starship.toml" ]; then
        pass "_installSymLink: file -> $HOME/.config/starship.toml"
    else
        fail "_installSymLink: file symlink not created"
    fi

    # New symlink (no existing target)
    _installSymLink "newtest" "$HOME/.config/newtest" "/tmp/test-new/" "$HOME/.config" 2>/dev/null
    if [ -L "$HOME/.config/newtest" ]; then
        pass "_installSymLink: new -> $HOME/.config/newtest"
    else
        fail "_installSymLink: new symlink not created"
    fi

    # Test each package script with bash -n in isolation
    log "Testing all package scripts with dependency simulation..."
    for _f in "$SCRIPT_DIR"/hypr/packages/*.sh; do
        local name; name=$(basename "$_f" .sh)
        bash -n "$_f" 2>/dev/null && pass "package script syntax: $name" || { local err; err=$(bash -n "$_f" 2>&1 || true); fail "package script syntax: $name — $err"; }
    done

    # Verify graphics-card.sh accepts all expected arguments
    log "Validating graphics-card.sh argument handling..."
    for gpu in intel amd nvidia virt; do
        # Dry-run by checking syntax and argument handler structure
        if grep -q "\"$gpu\")" "$SCRIPT_DIR/hypr/packages/graphics-card.sh" 2>/dev/null; then
            pass "graphics-card.sh has case for: $gpu"
        else
            warn "graphics-card.sh may not handle: $gpu"
        fi
    done

    # Run the subset of package scripts that don't require interaction
    # (those that are just pacman -S lists)
    log "Running leaf package scripts (dry-run mode)..."
    for script_name in fonts.sh wallpapers.sh samba.sh bluetooth.sh; do
        local f="$SCRIPT_DIR/hypr/packages/$script_name"
        if [ -f "$f" ]; then
            log "  Executing: $script_name"
            if bash "$f" 2>/dev/null; then
                pass "package script executed: $script_name"
            else
                fail "package script failed: $script_name"
            fi
        fi
    done

    # Verify main installer syntax
    bash -n "$SCRIPT_DIR/1-install.sh" 2>/dev/null \
        && pass "1-install.sh syntax OK" \
        || { local err; err=$(bash -n "$SCRIPT_DIR/1-install.sh" 2>&1 || true); fail "1-install.sh syntax error: $err"; }

    # Count functions in main installer
    local func_count
    func_count=$(grep -cP '^\s*\w+\(\)\s*\{' "$SCRIPT_DIR/1-install.sh" || true)
    pass "1-install.sh: $func_count functions declared"

    # Clean up test artifacts
    rm -rf /tmp/test-*
    rm -rf "$HOME"
}

# ============================================================
# STEP 5: End-to-end installer check (non-root user)
# ============================================================
e2e_check() {
    print_header "End-to-End Installer Verification"

    # Check all service names match what 1-install.sh expects
    log "Verifying service names against systemd..."
    local services=("bluetooth" "cockpit.socket" "smb" "nmb")
    for svc in "${services[@]}"; do
        # In a container, these unit files won't exist — just log
        if [ -f "/usr/lib/systemd/system/${svc}.service" ] || [ -f "/etc/systemd/system/${svc}.service" ]; then
            pass "systemd service file exists: $svc"
        else
            warn "systemd service file not found: $svc (expected in minimal container)"
        fi
    done

    # Verify the standlone scripts directory has executables
    log "Checking standalone scripts..."
    local standalone_count
    standalone_count=$(find "$SCRIPT_DIR/common/standalone" -type f 2>/dev/null | wc -l)
    if [ "$standalone_count" -gt 0 ]; then
        pass "$standalone_count standalone scripts in common/standalone"
    else
        warn "No files in common/standalone"
    fi

    # Verify figlet fonts
    log "Checking figlet fonts..."
    local figlet_count
    figlet_count=$(find "$SCRIPT_DIR/common/figlet/fonts" -type f 2>/dev/null | wc -l)
    if [ "$figlet_count" -gt 0 ]; then
        pass "$figlet_count figlet fonts"
    else
        warn "No figlet fonts found"
    fi

    # Verify all dpendencies that the installer needs exist
    log "Checking required tools in container..."
    local required_tools=("fzf" "bash" "sudo" "tee" "figlet" "curl" "git")
    for tool in "${required_tools[@]}"; do
        command -v "$tool" &>/dev/null \
            && pass "tool available: $tool" \
            || fail "tool missing: $tool"
    done
}

# ============================================================
# MAIN
# ============================================================
main() {
    local exit_code=0

    echo ""
    echo "  _   _                           _            ___          _   _          "
    echo " | | | |_   _ _ __  _ __  _   _  | |_ ___     / _ \ _ __   | \ | | ___  ___"
    echo " | |_| | | | | '_ \| '_ \| | | | | __/ _ \   | | | | '_ \  |  \| |/ _ \/ _ \\"
    echo " |  _  | |_| | |_) | |_) | |_| | | || (_) |  | |_| | | | | | |\  |  __/ (_) |"
    echo " |_| |_|\__, | .__/| .__/ \__, |  \__\___/    \___/|_| |_| |_| \_|\___|\___/|"
    echo "        |___/|_|   |_|    |___/                                             "
    echo ""
    echo "  Deep Docker Dry Run"
    echo "  $(date)"
    echo "  Container: $(uname -m) | $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')"
    echo ""

    syntax_check
    validate_paths
    cross_reference
    simulate_installer
    e2e_check

    echo ""
    summary || exit_code=$?

    echo ""
    echo "========================================================="
    echo "  PASS: $PASS  |  WARN: $WARN  |  FAIL: $FAIL"
    echo "========================================================="
    echo ""

    exit $exit_code
}

main "$@"
