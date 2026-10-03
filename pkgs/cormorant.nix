# Cormorant — a display serif by Christian Thalmann (Catharsis Fonts).
#
# Vendored rather than taken from nixpkgs, for a measured reason: Cormorant has
# no package of its own, and the obvious alternative —
#   google-fonts.override { fonts = [ "Cormorant" ]; }
# — filters at INSTALL time but still fetches the entire google/fonts repo
# first. That is 2810 MiB of download to end up with 880 KiB of font, which
# would roughly double the size of a whole system install.
#
# OFL-1.1 explicitly permits redistribution; the licence ships alongside the
# files in ../fonts/cormorant/OFL.txt and is installed with them.
{ lib, stdenvNoCC }:

stdenvNoCC.mkDerivation {
  pname = "cormorant";
  # Upstream doesn't version the Google Fonts drop; dated from the local copy.
  version = "0-unstable-2025-07-11";

  src = ../fonts/cormorant;

  dontConfigure = true;
  dontBuild = true;

  # Variable fonts only, deliberately. The two files carry the whole weight
  # axis, and installing the static instances alongside them would make
  # fontconfig register the same family twice and pick weights unpredictably.
  installPhase = ''
    runHook preInstall
    install -Dm444 -t "$out/share/fonts/truetype" ./*.ttf
    install -Dm444 -t "$out/share/doc/cormorant" ./OFL.txt
    runHook postInstall
  '';

  meta = {
    description = "Cormorant, a display serif in the Garamond tradition";
    homepage = "https://github.com/CatharsisFonts/Cormorant";
    license = lib.licenses.ofl;
    platforms = lib.platforms.all;
  };
}
