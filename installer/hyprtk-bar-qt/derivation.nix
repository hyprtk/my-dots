# hyprtk-bar-qt Nix derivation (Quickshell + Qt6).
#
# Packages the QML shell + Python backend + vendored pywal16. Requires
# Quickshell (`pkgs.quickshell`) and its Qt6 modules; if your nixpkgs revision
# does not provide Quickshell, add it as an input/overlay and point
# `quickshell` at it.
{ pkgs, lib, src, quickshell ? pkgs.quickshell }:

pkgs.stdenv.mkDerivation rec {
  pname = "hyprtk-bar-qt";
  version = "0.40.0";
  inherit src;

  nativeBuildInputs = [ pkgs.makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    outdir="$out/share/hyprtk-bar-qt"
    mkdir -p "$outdir" "$out/bin"
    cp -r shell.qml bar surface components config data state theme backend \
          bin scripts vendor assets themes Wallpapers "$outdir/"

    # Bundled pywal16: expose `wal` over the vendored tree (no pip/network).
    makeWrapper ${pkgs.python3.interpreter} "$out/bin/wal" \
      --prefix PYTHONPATH : "$outdir/vendor/pywal16" \
      --add-flags "-m pywal"

    # Main launcher: Quickshell pointed at the installed shell.
    makeWrapper ${quickshell}/bin/qs "$out/bin/hyprtk-bar-qt" \
      --prefix PATH : "$out/bin" \
      --add-flags "-p $outdir"

    # Glyph icons use the "Symbols Nerd Font" family; ship the bundled TTF.
    install -Dm644 assets/fonts/SymbolsNerdFont-Regular.ttf \
      "$out/share/fonts/truetype/SymbolsNerdFont-Regular.ttf"
    runHook postInstall
  '';

  meta = with lib; {
    description = "Hyprtk status bar for Hyprland (Quickshell/QML)";
    license = licenses.gpl2Only;
    platforms = platforms.linux;
    mainProgram = "hyprtk-bar-qt";
  };
}
