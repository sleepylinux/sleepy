{
  lib,
  writeShellApplication,
  nix,
  nixos-rebuild,
  coreutils,
  dialog,
}:
writeShellApplication {
  name = "sleepy-system";
  runtimeInputs = [nix nixos-rebuild coreutils dialog];
  text =
    builtins.replaceStrings
    ["@rebuild@" "@dialogrc@"]
    ["${nixos-rebuild}/bin/nixos-rebuild" "${../sleepy-installer/dialogrc}"]
    (builtins.readFile ./sleepy-system.sh);
  meta = {
    description = "Sleepy terminal system status and recovery menu";
    license = lib.licenses.gpl3Only;
    platforms = lib.platforms.linux;
    mainProgram = "sleepy-system";
  };
}
