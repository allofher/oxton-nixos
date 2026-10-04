{
  description = "oxton desktop — ssh target / home daemons / ROCm compute / Steam";

  inputs = {
    # Matches your 26.05 install ISO. Bump the channel when you want to upgrade.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Fast-moving packages only, exposed as pkgs.unstable.*. The 26.05 release
    # branch only gets cherry-picks, and some packages stop being backported
    # long before the branch goes EOL — claude-code froze at 2.1.223 on
    # 2026-08-06 while master kept tracking releases daily. Nothing in a flake
    # update fixes that; the package has to come off a branch that still moves.
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs, nixpkgs-unstable, ... }:
    let
      system = "x86_64-linux";
    in {
      # `nixos-rebuild switch --flake .#oxton`
      # `nix flake init -t ~/nixos#node` in a new project directory.
      templates = {
        node = {
          path = ./templates/node-project;
          description = "Node dev shell, with the native-module build deps wired up";
        };
        default = self.templates.node;
      };

      nixosConfigurations.oxton = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          {
            # allowUnfree has to be set on this import too: the
            # nixpkgs.config.allowUnfree in configuration.nix only applies to
            # the stable instance, and claude-code is unfree.
            nixpkgs.overlays = [
              (final: prev: {
                unstable = import nixpkgs-unstable {
                  inherit system;
                  config.allowUnfree = true;
                };
              })
            ];
          }
          ./configuration.nix
          # ./hardware-configuration.nix is imported from configuration.nix,
          # and is generated on the machine during install.
        ];
      };
    };
}
