{
  description = "Codepen clone";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        packages.${system}.rin = { };

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
