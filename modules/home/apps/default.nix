{
  config,
  lib,
  pkgs,
  ...
}: let
  picturesDir =
    if config.xdg.userDirs.pictures == null
    then "${config.home.homeDirectory}/Pictures"
    else config.xdg.userDirs.pictures;
in {
  config = lib.mkIf config.sleepy.enable {
    programs = {
      firefox.enable = true;

      fish.enable = true;
      imv.enable = lib.mkDefault true;

      swappy = {
        enable = lib.mkDefault true;
        settings.Default = {
          save_dir = lib.mkDefault "${picturesDir}/Screenshots";
          save_filename_format = lib.mkDefault "Sleepy-%Y%m%d-%H%M%S.png";
          show_panel = lib.mkDefault true;
        };
      };

      ghostty = {
        enable = true;
        settings = lib.mapAttrsRecursive (_path: lib.mkDefault) {
          command = "${pkgs.fish}/bin/fish";
          background = "181620";
          foreground = "e8e2f0";
          cursor-color = "b9a7ff";
          selection-background = "302a3d";
          selection-foreground = "ffffff";
        };
      };

      fuzzel = {
        enable = true;
        settings = lib.mapAttrsRecursive (_path: lib.mkDefault) {
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

    xdg.mimeApps = lib.mkIf config.programs.imv.enable {
      enable = lib.mkDefault true;
      defaultApplications = lib.genAttrs [
        "image/png"
        "image/jpeg"
        "image/gif"
        "image/webp"
        "image/tiff"
        "image/bmp"
        "image/svg+xml"
      ] (_: lib.mkDefault ["imv.desktop"]);
    };

    gtk = {
      enable = lib.mkDefault true;
      theme = {
        name = lib.mkDefault "adw-gtk3-dark";
        package = lib.mkDefault pkgs.adw-gtk3;
      };
      iconTheme = {
        name = lib.mkDefault "Papirus-Dark";
        package = lib.mkDefault pkgs.papirus-icon-theme;
      };
      gtk3.extraConfig.gtk-application-prefer-dark-theme = lib.mkDefault true;
    };
    dconf.settings."org/gnome/desktop/interface".color-scheme = lib.mkDefault "prefer-dark";
  };
}
