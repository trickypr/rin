{ pkgs, rin-web, ... }:
let
  web = "${rin-web}/lib/node_modules/rin-web";
in
pkgs.buildGleamApplication {
  src = ./.;
  rebar3Package = pkgs.rebar3WithPlugins { plugins = with pkgs.beamPackages; [ pc ]; };

  postConfigure = ''
    mkdir -p priv/bundled
    cp -r ${web}/css ./priv
    cp -r ${web}/js/* ./priv/bundled
    touch priv/is-nix-pkg
  '';
}
