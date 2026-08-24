{
  config,
  lib,
  pkgs,
  ...
}: let
  sleepyctl = "${config.sleepy.sessionPackage}/bin/sleepyctl";
  niri = "${pkgs.niri}/bin/niri";
  onlineReconcile = pkgs.writeShellScript "sleepy-bindings-online" ''
    export SLEEPYCTL=${lib.escapeShellArg sleepyctl}
    export SLEEPY_JQ=${lib.escapeShellArg "${pkgs.jq}/bin/jq"}
    export SLEEPY_SYSTEMCTL=${lib.escapeShellArg "${pkgs.systemd}/bin/systemctl"}
    export SLEEPY_SLEEP=${lib.escapeShellArg "${pkgs.coreutils}/bin/sleep"}
    export SLEEPY_SOCKET_ATTEMPTS=150
    ${builtins.readFile ./online-reconcile.sh}
  '';
in {
  config = lib.mkIf (config.sleepy.enable && config.sleepy.sessionPackage != null) {
    home.packages = [
      config.sleepy.sessionPackage
      pkgs.networkmanager
      pkgs.bluez
      pkgs.wireplumber
      pkgs.brightnessctl
      pkgs.power-profiles-daemon
      pkgs.upower
      pkgs.playerctl
      pkgs.gammastep
      pkgs.swaylock
      pkgs.niri
      pkgs.systemd
      pkgs.quickshell
    ];

    home.sessionVariables = {
      SLEEPY_NIRI = niri;
      SLEEPY_NIRI_VALIDATOR = niri;
    };

    home.activation.sleepyBindings = lib.hm.dag.entryAfter ["linkGeneration"] ''
      export SLEEPY_NIRI=${lib.escapeShellArg niri}
      export SLEEPY_NIRI_VALIDATOR=${lib.escapeShellArg niri}
      unset NIRI_SOCKET
      ${sleepyctl} bindings reconcile
      generated_bindings=${lib.escapeShellArg "${config.xdg.configHome}/niri/sleepy-user-bindings.kdl"}
      if test -L "$generated_bindings"; then
        echo "Sleepy refuses a symlink at the generated bindings path" >&2
        exit 1
      fi
      if ! test -e "$generated_bindings"; then
        ${sleepyctl} bindings initialize
      elif ! test -f "$generated_bindings"; then
        echo "Sleepy requires the generated bindings path to be a regular file" >&2
        exit 1
      fi
    '';

    systemd.user.services.sleepy-session = {
      Unit = {
        Description = "Initialize Sleepy session settings state";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
        Requisite = ["graphical-session.target"];
      };

      Service = {
        Type = "oneshot";
        ExecStart = "${config.sleepy.sessionPackage}/bin/sleepyctl settings show";
        RemainAfterExit = true;
      };

      Install.WantedBy = ["graphical-session.target"];
    };

    systemd.user.services.sleepy-bindings-online = {
      Unit = {
        Description = "Confirm Sleepy generated bindings in the running Niri session";
        PartOf = ["graphical-session.target"];
        After = ["niri.service"];
        Requires = ["niri.service"];
      };
      Service = {
        Type = "oneshot";
        ExecStart = onlineReconcile;
        Environment = [
          "SLEEPY_NIRI=${niri}"
          "SLEEPY_NIRI_VALIDATOR=${niri}"
        ];
        RemainAfterExit = true;
      };
      Install.WantedBy = ["graphical-session.target"];
    };

    systemd.user.services.gammastep = {
      Unit.Description = "Sleepy managed night-light provider";
      Service = {
        Type = "simple";
        # Equal day/night temperatures make the neutral location irrelevant:
        # service active means a continuously held 4500 K, stop resets it.
        ExecStart = "${pkgs.gammastep}/bin/gammastep -m wayland -l 0:0 -t 4500:4500";
        Restart = "on-failure";
      };
    };
  };
}
