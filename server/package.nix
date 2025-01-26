{ pkgs, ... }:
pkgs.buildGleamApplication {
  src = ./.;
  rebar3Package = pkgs.rebar3WithPlugins { plugins = with pkgs.beamPackages; [ pc ]; };

  postConfigure = ''
    mkdir -p priv
    touch priv/is-nix-pkg
  '';
}
