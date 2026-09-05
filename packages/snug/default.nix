{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  nix,
  git,
  nixos-rebuild,
  coreutils,
}:
stdenvNoCC.mkDerivation {
  pname = "snug";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [makeWrapper];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/snug $out/bin
    cp *.py $out/lib/snug/
    install -Dm644 ${../../docs/snug.md} $out/share/doc/snug/README.md
    makeWrapper ${python3}/bin/python3 $out/bin/snug \
      --add-flags "$out/lib/snug/snug.py" \
      --prefix PATH : ${lib.makeBinPath [nix git nixos-rebuild coreutils]}
    runHook postInstall
  '';
  meta = {
    description = "Friendly package, development and rolling update CLI for Sleepy Linux";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "snug";
  };
}
