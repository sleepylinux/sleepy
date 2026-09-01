{
  config,
  lib,
  pkgs,
  ...
}: let
  userConfig = "${config.xdg.configHome}/hypr/sleepy-user.conf";
in {
  config = lib.mkIf config.sleepy.enable {
    wayland.windowManager.hyprland = {
      enable = true;
      package = null;
      portalPackage = null;
      configType = "hyprlang";

      # UWSM owns graphical-session.target and the compositor scope. Home
      # Manager is responsible only for the deterministic Hyprland config.
      systemd.enable = false;

      settings = lib.mkMerge [
        (import ./settings.nix)
        (import ./appearance.nix)
        (import ./rules.nix {inherit config;})
        (import ./binds.nix {inherit config;})
      ];

      # This mutable, user-owned include is initialized once below and is
      # never replaced by a later Home Manager generation.
      extraConfig = ''
        source = ${userConfig}
      '';
    };

    # UWSM imports the same Home Manager environment as interactive shells.
    xdg.configFile."uwsm/env".source =
      "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";

    home.activation.sleepyHyprlandUserConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
      hyprland_dir=${lib.escapeShellArg "${config.xdg.configHome}/hypr"}
      user_config=${lib.escapeShellArg userConfig}

      if test -L "$hyprland_dir" || { test -e "$hyprland_dir" && ! test -d "$hyprland_dir"; }; then
        echo "Sleepy refuses a non-directory Hyprland configuration path" >&2
        exit 1
      fi
      if ! test -d "$hyprland_dir"; then
        ${pkgs.coreutils}/bin/install -d -m 0700 "$hyprland_dir"
      fi

      if test -L "$user_config"; then
        echo "Sleepy refuses a symlink at the Hyprland user override path" >&2
        exit 1
      elif test -e "$user_config" && ! test -f "$user_config"; then
        echo "Sleepy requires the Hyprland user override path to be a regular file" >&2
        exit 1
      elif ! test -e "$user_config"; then
        ${pkgs.coreutils}/bin/install -m 0600 /dev/null "$user_config"
      fi
    '';
  };
}
