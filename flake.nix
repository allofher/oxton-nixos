{
  description = "oxton desktop — ssh target / home daemons / ROCm compute / Steam";

  inputs = {
    # Track a stable channel; bump to nixos-25.11 etc. when you want.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
  };

  outputs = { self, nixpkgs, ... }:
    let
      system = "x86_64-linux";
    in {
      # `nixos-rebuild switch --flake .#oxton`
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
