{ stdenv
, fetchurl
,
}:
stdenv.mkDerivation {
  pname = "opi5x-firmware";
  version = "latest";

  src = ./firmware;

  buildCommand = ''
    mkdir $out/lib -p
    cp -Rf $src $out/lib/firmware
  '';
}
