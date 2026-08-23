{
  pkgs,
  primaryUser,
  ...
}: let
  ghostty = pkgs.symlinkJoin {
    name = "ghostty-sleepy-vm-${pkgs.ghostty.version}";
    paths = [pkgs.ghostty];
    nativeBuildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram "$out/bin/ghostty" --set LIBGL_ALWAYS_SOFTWARE 1
    '';
    meta = pkgs.ghostty.meta;
    passthru =
      pkgs.ghostty.passthru
      // {
        inherit (pkgs.ghostty) vim;
      };
  };
in {
  home-manager.users.${primaryUser}.programs.ghostty.package = ghostty;
}
