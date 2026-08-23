{stdenvNoCC}:
stdenvNoCC.mkDerivation {
  pname = "sleepy-branding";
  version = "0.1.0";
  src = ./logo.svg;
  dontUnpack = true;
  installPhase = ''
    runHook preInstall
    install -Dm644 "$src" "$out/share/sleepy/branding/logo.svg"
    runHook postInstall
  '';
}
