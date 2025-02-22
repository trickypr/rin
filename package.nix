{
  rin-web,
  rin-server,
  pkgs,
  ...
}:
let
  web = "${rin-web}/lib/node_modules/rin-web";
in
pkgs.writeShellScriptBin "rin" ''
  IS_NIX=true WEB_DIRECTORY=${web}/out ${rin-server}/bin/rin
''
