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

        web-dev = pkgs.writeShellScriptBin "web-dev" "(cd web && mkdir -p out && ln -s ../css ./out/css && npm run bundle:watch)";
        server-dev = pkgs.writeShellScriptBin "server-dev" "(cd server && gleam run)";

        dev = pkgs.writeShellScriptBin "dev" "${pkgs.parallel}/bin/parallel --tag ::: web-dev server-dev";
      in
      {
        packages =
          let
            server-pkg = import ./server/package.nix;
            web-pkg = import ./web/package.nix;
            integration = import ./package.nix;
          in
          rec {
            rin-web = web-pkg pkgs;
            rin-server = server-pkg pkgs;
            rin = integration {
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
            nodejs

            web-dev
            server-dev
            dev
          ];

          shellHook = ''
            export JWT_SECRET=$(${pkgs.libossp_uuid}/bin/uuid)
            export WEB_DIRECTORY=$(pwd)/web/out
          '';
        };
      }
    );
}
