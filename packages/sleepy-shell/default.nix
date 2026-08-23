{
  sleepy-branding,
  stdenvNoCC,
}:
stdenvNoCC.mkDerivation {
  pname = "sleepy-shell";
  version = "0.1.0";
  src = ./src;
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/share/quickshell/sleepy"
    cp -R . "$out/share/quickshell/sleepy/"
    substituteInPlace "$out/share/quickshell/sleepy/shell.qml" \
      --replace-fail "@sleepyBrandingLogo@" "${sleepy-branding}/share/sleepy/branding/logo.svg"
    runHook postInstall
  '';
}
