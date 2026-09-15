{
  lib,
  writeShellApplication,
  nix,
  nixos-rebuild,
  sleepy-update,
  coreutils,
  dialog,
  jq,
}:
writeShellApplication {
  name = "sleepy-system";
  runtimeInputs = [nix nixos-rebuild coreutils dialog jq];
  text =
    builtins.replaceStrings
    ["@rebuild@" "@dialogrc@" "@update@"]
    ["${nixos-rebuild}/bin/nixos-rebuild" "${../sleepy-installer/dialogrc}" "${sleepy-update}/bin/sleepy-update"]
    (builtins.readFile ./sleepy-system.sh);
  meta = {
    description = "Sleepy terminal system status and recovery menu";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "sleepy-system";
  };
}
