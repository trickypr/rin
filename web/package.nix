{ pkgs, system, ... }:
let
  npm-pkg = pkgs.buildNpmPackage {
    pname = "rin-web";
    version = "1.0.0";
    src = ./.;
    npmDepsHash = "sha256-FIs74JtHf4uUE82ioHn0aUS8q3ImzFI4cTyq7USuAno=";
  };
in
derivation {
  name = "rin-web";
  builder = "${pkgs.bash}/bin/bash";
  system = system;
  args = [
    "-c"
    ''
      ${pkgs.coreutils}/bin/mkdir -p $out/css 
      ${pkgs.coreutils}/bin/cp -r ${npm-pkg}/lib/node_modules/rin-web/out $out
      ${pkgs.coreutils}/bin/cp -r ${npm-pkg}/lib/node_modules/rin-web/css/* $out/css
    ''
  ];
}
