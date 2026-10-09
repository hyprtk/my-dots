{
  description = "hyprtk-bar-qt — Quickshell/QML status bar for Hyprland";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f (import nixpkgs { inherit system; }));
    in {
      packages = forAllSystems (pkgs: {
        default = pkgs.callPackage ./derivation.nix { src = self; };
        hyprtk-bar-qt = pkgs.callPackage ./derivation.nix { src = self; };
      });

      apps = forAllSystems (pkgs:
        let pkg = self.packages.${pkgs.system}.default; in {
          default = { type = "app"; program = "${pkg}/bin/hyprtk-bar-qt"; };
        });
    };
}
