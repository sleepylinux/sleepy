{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  util-linux,
  pciutils,
  parted,
  e2fsprogs,
  dosfstools,
  systemd,
  nix,
  nixos-install-tools,
  coreutils,
  git,
  networkmanager,
}:
stdenvNoCC.mkDerivation {
  pname = "sleepy-installer";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [makeWrapper];
  installPhase = ''
    runHook preInstall
    install -Dm755 installer.py $out/libexec/sleepy-installer.py
    makeWrapper ${python3}/bin/python3 $out/bin/sleepy-install \
      --add-flags $out/libexec/sleepy-installer.py \
      --prefix PATH : ${lib.makeBinPath [util-linux pciutils parted e2fsprogs dosfstools systemd nix nixos-install-tools coreutils git networkmanager]}
    runHook postInstall
  '';
  meta.license = lib.licenses.gpl3Only;
  meta = {
    description = "Sleepy Linux terminal onboarding and guarded whole-disk installer";
    platforms = ["x86_64-linux"];
    mainProgram = "sleepy-install";
  };
}
