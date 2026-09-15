{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  nix,
}:
stdenvNoCC.mkDerivation {
  pname = "sleepy-update";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [makeWrapper];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/sleepy-update $out/bin
    cp updater.py $out/lib/sleepy-update/
    makeWrapper ${python3}/bin/python3 $out/bin/sleepy-update \
      --add-flags $out/lib/sleepy-update/updater.py \
      --prefix PATH : ${lib.makeBinPath [nix]}
    runHook postInstall
  '';
  meta = {
    description = "Constrained preparation of approved Sleepy candidates for next boot";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "sleepy-update";
  };
}
