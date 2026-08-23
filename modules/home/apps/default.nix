{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.sleepy.enable {
    programs = {
      firefox.enable = true;

      fish.enable = true;

      ghostty = {
        enable = true;
        settings = {
          command = "${pkgs.fish}/bin/fish";
          background = "181620";
        };
      };

      fuzzel = {
        enable = true;
        settings = {
          main = {
            terminal = "${config.programs.ghostty.package}/bin/ghostty";
            width = 36;
            lines = 8;
            font = "sans:size=11";
            horizontal-pad = 12;
            vertical-pad = 8;
            inner-pad = 6;
          };

          colors = {
            background = "181620ff";
            text = "e8e2f0ff";
            match = "b9a7ffff";
            selection = "302a3dff";
            selection-text = "ffffffff";
            selection-match = "b9a7ffff";
            border = "5d526fff";
          };

          border = {
            width = 1;
            radius = 8;
          };
        };
      };
    };
  };
}
