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
        (import ./binds.nix {inherit config pkgs;})
      ];

      # This mutable, user-owned include is initialized once below and is
      # never replaced by a later Home Manager generation.
      extraConfig = ''
        source = ${userConfig}
      '';
    };

    # UWSM imports the same Home Manager environment as interactive shells.
    xdg.configFile."uwsm/env".source = "${config.home.sessionVariablesPackage}/etc/profile.d/hm-session-vars.sh";

    home.activation.sleepyHyprlandUserConfig = lib.hm.dag.entryAfter ["linkGeneration"] ''
      hyprland_dir=${lib.escapeShellArg "${config.xdg.configHome}/hypr"}
      user_config=${lib.escapeShellArg userConfig}
      ${pkgs.bash}/bin/bash ${./ensure-user-config.sh} \
        "$hyprland_dir" \
        "$user_config" \
        ${pkgs.coreutils}/bin/install \
        ${pkgs.coreutils}/bin/chmod
    '';
  };
}
