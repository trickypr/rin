{ pkgs, ... }:
pkgs.buildGleamApplication {
  src = ./.;
  rebar3Package = pkgs.rebar3WithPlugins { plugins = with pkgs.beamPackages; [ pc ]; };
}
