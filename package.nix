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

  installPhase = ''
    mkdir $out
    cp -r --no-preserve=mode,ownership ${rin-server}/* $out
    cp -r ${web}/css $out/lib/rin/priv
    cp -r ${web}/out $out/lib/rin/priv
    chmod +x $out/bin/rin
  '';
}
