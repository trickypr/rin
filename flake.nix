{
  description = "Codepen clone";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-gleam = {
      url = "github:arnarg/nix-gleam";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      nix-gleam,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ nix-gleam.overlays.default ];
        };
      in
      {
        packages = rec {
          rin = pkgs.buildGleamApplication {
            src = ./.;
            rebar3Package = pkgs.rebar3WithPlugins { plugins = with pkgs.beamPackages; [ pc ]; };
          };
          default = rin;
        };

        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            esbuild
            glas
            gleam
          ];

          shellHook = ''
            export JWT_SECRET=$(${pkgs.libossp_uuid}/bin/uuid)
          '';
        };
      }
    );
}
