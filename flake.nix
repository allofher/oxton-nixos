{
  description = "oxton desktop — ssh target / home daemons / ROCm compute / Steam";

  inputs = {
    # Matches your 26.05 install ISO. Bump the channel when you want to upgrade.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
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
          ./configuration.nix
          # ./hardware-configuration.nix is imported from configuration.nix,
          # and is generated on the machine during install.
        ];
      };
    };
}
