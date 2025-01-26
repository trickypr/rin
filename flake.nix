{
  description = "Codepen clone";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix-gleam.url = "github:arnarg/nix-gleam";
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
        packages =
          let
            server-pkg = import ./server/package.nix;
            web-pkg = import ./web/package.nix;
            rin-pkg = import ./package.nix;
          in
          rec {
            rin-web = web-pkg pkgs;
            rin-server = server-pkg pkgs;
            rin = rin-pkg {
              stdenv = pkgs.stdenv;
              inherit pkgs;
              inherit rin-web;
              inherit rin-server;
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
