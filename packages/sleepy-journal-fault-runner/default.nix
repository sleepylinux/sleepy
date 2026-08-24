{
  lib,
  pkgs,
  sleepy-session,
}:
(pkgs.writeShellScriptBin "sleepy-journal-fault-runner" (
  builtins.replaceStrings
  ["@coreutils@" "@jq@" "@sleepyctl@"]
  [
    "${pkgs.coreutils}/bin"
    "${pkgs.jq}/bin/jq"
    "${sleepy-session}/bin/sleepyctl"
  ]
  (builtins.readFile ./runner.sh)
)).overrideAttrs (_old: {
  meta.description = "Sleepy deployment journal recovery acceptance runner";
  meta.license = lib.licenses.gpl3Only;
  meta.mainProgram = "sleepy-journal-fault-runner";
  meta.platforms = lib.platforms.linux;
})
