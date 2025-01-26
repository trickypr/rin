{
  stdenv,
  rin-web,
  rin-server,
  ...
}:
let
  web = "${rin-web}/lib/node_modules/rin-web";
in
stdenv.mkDerivation {
  name = "rin";
  src = ./.;

  install = ''
    cp -r ${rin-server}/* $out
    cp -r ${web}/css $out/lib/rin/priv
    cp -r ${web}/out/bundled $out/lib/rin/priv
  '';
}
