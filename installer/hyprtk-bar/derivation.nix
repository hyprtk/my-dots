# hyprtk-bar Nix derivation (Python 3 + GTK3 + gtk-layer-shell).
#
# Follows the nwg-displays pattern (the same PyGObject3/GTK3/gtk-layer-shell
# stack): buildPythonApplication + wrapGAppsHook + gobject-introspection, with
# the GI typelib libs in propagatedBuildInputs so their typelibs reach
# GI_TYPELIB_PATH.
#
# Data files (assets/, scripts/, themes/) are installed to
# $out/share/hyprtk-bar and surfaced to the app via HYPRTK_BAR_DATA_DIR, which
# config.py reads instead of deriving the location from __file__ (which breaks
# once the package is unpacked into site-packages).
#
# NOTE: `wrapGAppsHook` (classic) is used for maximum nixpkgs compatibility;
# `wrapGAppsHook3` is the newer GTK3-specific replacement on recent nixpkgs.
{ pkgs, lib, src }:

pkgs.python3Packages.buildPythonApplication rec {
  pname = "hyprtk-bar";
  version = "0.2.0";
  pyproject = true;
  inherit src;

  nativeBuildInputs = [
    pkgs.wrapGAppsHook
    pkgs.gobject-introspection
    pkgs.makeWrapper
  ];

  buildInputs = [
    pkgs.gtk3
    pkgs.cairo
  ];

  propagatedBuildInputs = with pkgs; [
    pango
    gtk-layer-shell
    gdk-pixbuf
    python3Packages.pygobject3
    python3Packages.pycairo
    python3Packages.dbus-next
  ];

  # buildPythonApplication already wraps the executable; fold the GTK wrapper
  # args in instead of wrapping twice.
  dontWrapGApps = true;
  preFixup = ''
    makeWrapperArgs+=( "''${gappsWrapperArgs[@]}" )
  '';

  postInstall = ''
    cp -r assets "$out/share/hyprtk-bar/assets"
    cp -r scripts "$out/share/hyprtk-bar/scripts"
    cp -r themes "$out/share/hyprtk-bar/themes"
    # Vendored pywal16 (see vendor/pywal16/VENDOR.md) — the bar and its scripts
    # call `wal`; expose it as a wrapper over this same Python + the vendored
    # tree, so no separate pywal package is needed.
    cp -r vendor "$out/share/hyprtk-bar/vendor"
    makeWrapper ${pkgs.python3Packages.python.interpreter} "$out/bin/wal" \
      --prefix PYTHONPATH : "$out/share/hyprtk-bar/vendor/pywal16" \
      --add-flags "-m pywal"
    # The glyph icons are rendered with the "Symbols Nerd Font" family; ship the
    # bundled TTF so fontconfig finds it via XDG_DATA_DIRS (wrapGAppsHook adds
    # $out/share). Users with nerd-fonts installed don't need this copy.
    install -Dm644 assets/fonts/SymbolsNerdFont-Regular.ttf \
      "$out/share/fonts/truetype/SymbolsNerdFont-Regular.ttf"
  '';

  makeWrapperArgs = [
    "--set" "HYPRTK_BAR_DATA_DIR" "$out/share/hyprtk-bar"
    # Put the bundled `wal` wrapper on the bar's PATH so it resolves at runtime.
    "--prefix" "PATH" ":" "$out/bin"
  ];

  meta = with lib; {
    description = "Hyprtk status bar for Hyprland (GTK3 + layer shell)";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
    mainProgram = "hyprtk-bar";
    maintainers = [ maintainers.hyprtk ];
  };
}
