{
  lib,
  pkgs,
  sleepy-session,
}: let
  fsHelper = pkgs.stdenv.mkDerivation {
    pname = "sleepy-journal-fs";
    version = "0.1.0";
    src = ./journal-fs.c;
    dontUnpack = true;
    buildPhase = ''
      runHook preBuild
      $CC -std=c11 -O2 -Wall -Wextra -Werror "$src" -o sleepy-journal-fs
      runHook postBuild
    '';
    installPhase = ''
      runHook preInstall
      install -Dm0555 sleepy-journal-fs "$out/bin/sleepy-journal-fs"
      runHook postInstall
    '';
    meta.license = lib.licenses.gpl3Only;
  };
in
  (pkgs.writeShellScriptBin "sleepy-journal-fault-runner" (
    builtins.replaceStrings
    ["@coreutils@" "@fshelper@" "@jq@" "@sleepyctl@"]
    [
      "${pkgs.coreutils}/bin"
      "${fsHelper}/bin/sleepy-journal-fs"
      "${pkgs.jq}/bin/jq"
      "${sleepy-session}/bin/sleepyctl"
    ]
    (builtins.readFile ./runner.sh)
  )).overrideAttrs (_old: {
    meta = {
      description = "Sleepy deployment journal recovery acceptance runner";
      license = lib.licenses.gpl3Only;
      mainProgram = "sleepy-journal-fault-runner";
      platforms = lib.platforms.linux;
    };
    passthru = {inherit fsHelper;};
  })
