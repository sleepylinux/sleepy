{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  dialog,
  util-linux,
  parted,
  btrfs-progs,
  dosfstools,
  nix,
  nixos-install-tools,
  systemd,
  coreutils,
  shadow,
  tzdata,
  kbd,
  source,
}:
stdenvNoCC.mkDerivation {
  pname = "sleepy-installer";
  version = "0.1.0-alpha";
  src = ./.;
  nativeBuildInputs = [makeWrapper];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/sleepy-installer $out/bin
    cp backend.py tui.py dialogrc $out/lib/sleepy-installer/
    makeWrapper ${python3}/bin/python3 $out/bin/sleepy-install-backend \
      --add-flags $out/lib/sleepy-installer/backend.py \
      --set SLEEPY_SOURCE ${source} \
      --set TZDIR ${tzdata}/share/zoneinfo \
      --set SLEEPY_ZONEINFO ${tzdata}/share/zoneinfo \
      --prefix PATH : ${lib.makeBinPath [util-linux parted btrfs-progs dosfstools nix nixos-install-tools systemd coreutils shadow kbd]}
    makeWrapper ${python3}/bin/python3 $out/bin/sleepy-install \
      --add-flags $out/lib/sleepy-installer/tui.py \
      --set SLEEPY_BACKEND $out/bin/sleepy-install-backend \
      --set PYTHONTZPATH ${tzdata}/share/zoneinfo \
      --prefix PATH : ${lib.makeBinPath [dialog]}
    runHook postInstall
  '';
  meta.description = "Sleepy minimal terminal installer";
  meta.license = lib.licenses.gpl3Only;
  meta.platforms = ["x86_64-linux"];
  meta.mainProgram = "sleepy-install";
}
