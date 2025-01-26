{ pkgs, ... }:
pkgs.buildNpmPackage {
  pname = "rin-web";
  version = "1.0.0";
  src = ./.;
  npmDepsHash = "sha256-FIs74JtHf4uUE82ioHn0aUS8q3ImzFI4cTyq7USuAno=";
}
