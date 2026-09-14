{
  description = "Hyprtk status bar for Hyprland (GTK3 + layer shell)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      pkgsFor = eachSystem (system: import nixpkgs { inherit system; });
    in
    {
      packages = eachSystem (system: {
        default = pkgsFor.${system}.callPackage ./derivation.nix { src = self; };
      });

      devShells = eachSystem (system:
        let pkgs = pkgsFor.${system};
        in {
          default = pkgs.mkShell {
            nativeBuildInputs = with pkgs; [ wrapGAppsHook gobject-introspection ];
            buildInputs = with pkgs; [
              (python3.withPackages (ps: [ ps.pygobject3 ps.pycairo ps.dbus-next ]))
              gtk3
              gtk-layer-shell
              pango
              gdk-pixbuf
              cairo
            ];
            shellHook = ''
              export GI_TYPELIB_PATH="$GI_TYPELIB_PATH''${GI_TYPELIB_PATH:+:}$(pwd)/build"
              # Bundled pywal16: expose `wal` from the vendored tree (VENDOR.md).
              export PYTHONPATH="$(pwd)/vendor/pywal16''${PYTHONPATH:+:$PYTHONPATH}"
              wal() { python3 -m pywal "$@"; }
            '';
          };
        });
    };
}
