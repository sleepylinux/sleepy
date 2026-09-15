{
  config,
  pkgs,
  ...
}: let
  welcome = pkgs.writeShellApplication {
    name = "sleepy-welcome";
    runtimeInputs = [pkgs.dialog pkgs.coreutils];
    text = ''
      export DIALOGRC=${../../../packages/sleepy-installer/dialogrc}
      state="''${XDG_STATE_HOME:-$HOME/.local/state}/sleepy"
      mkdir -p "$state"
      if dialog --title ' Welcome to Sleepy ' --msgbox \
        'Your desktop is ready to explore.\n\nSuper + Return: terminal\nSuper + D: launcher\nSuper + Q: close window; Print: select and save a screenshot\nShift + Print: copy a screen region\nNetwork and audio controls live in the shell.\nPersonal Hyprland changes: ~/.config/hypr/sleepy-user.conf\n\nsleepy-system generations: list recovery points\nsleepy-system rebuild: apply your saved system configuration\nsleepy-system rollback: return to the previous generation\n\nIf login fails, reboot and choose an older generation in the boot menu (hold Space). The installer also has a Recovery entry.\n\nThis is alpha software. Keep backups of important files.' 23 76; then
        touch "$state/welcome-seen"
      fi
    '';
  };
  systemTools = pkgs.writeShellApplication {
    name = "sleepy-system";
    runtimeInputs = [config.nix.package config.system.build.nixos-rebuild pkgs.coreutils];
    text = ''
      case "''${1:-help}" in
        generations) exec nix-env --list-generations -p /nix/var/nix/profiles/system ;;
        rebuild) exec sudo ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --flake /etc/nixos#installed ;;
        rollback) exec sudo ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --rollback ;;
        *) printf '%s\n' 'sleepy-system generations | rebuild | rollback' ;;
      esac
    '';
  };
in {
  environment.systemPackages = [welcome systemTools pkgs.thunar];
  services.gvfs.enable = true;
  # A failed/dismissed welcome never prevents the desktop from starting.
  systemd.user.services.sleepy-welcome = {
    description = "Sleepy first login welcome";
    wantedBy = ["graphical-session.target"];
    after = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    unitConfig.ConditionPathExists = "!%h/.local/state/sleepy/welcome-seen";
    serviceConfig = {
      # The interactive dialog may remain open for the whole session. Complete
      # its start job after exec so UWSM can stop the session while it is open.
      Type = "exec";
      ExecStart = "${pkgs.ghostty}/bin/ghostty -e ${welcome}/bin/sleepy-welcome";
    };
  };
}
