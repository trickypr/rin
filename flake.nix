{
  description = "Codepen clone";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    untracked = {
      url = "path:.";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      untracked,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            esbuild
            glas
            gleam
          ];

          shellHook = ''
            export JWT_SECRET=$(${pkgs.libossp_uuid}/bin/uuid)
            ${if builtins.pathExists "${untracked}/.env" then builtins.readFile "${untracked}/.env" else ""}
          '';
        };
      }
    );
}
