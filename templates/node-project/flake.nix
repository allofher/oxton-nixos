{
  description = "node dev shell";

  inputs = {
    # Same channel as the system, so the project and the OS agree on library
    # versions. Pin this independently if a project needs to lag or lead.
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          # Swap for nodejs_22 or nodejs_26 when a project needs a specific
          # major. Inside this shell it shadows the system-wide node on PATH,
          # so there's nothing to "switch" and nothing to remember.
          nodejs

          # Pick one. npm ships inside nodejs, so it needs no entry here.
          pnpm

          # Native-module build deps. Most projects need NONE of this — but
          # anything going through node-gyp does, and this is the part a
          # version manager could never provide. Uncomment what a build asks
          # for; the error will name the missing library.
          python3
          pkg-config
          # vips                                 # sharp
          # sqlite                               # better-sqlite3
          # cairo pango libjpeg giflib librsvg   # canvas
        ];

        shellHook = ''
          echo "node $(node --version), pnpm $(pnpm --version)"
        '';
      };
    };
}
