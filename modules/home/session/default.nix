{
  config,
  lib,
  pkgs,
  ...
}: let
  sleepyctl = "${config.sleepy.sessionPackage}/bin/sleepyctl";
  niri = "${pkgs.niri}/bin/niri";
  onlineReconcile = pkgs.writeShellScript "sleepy-bindings-online" ''
    set -eu
    attempt=0
    while test "$attempt" -lt 50; do
      NIRI_SOCKET=$(${pkgs.systemd}/bin/systemctl --user show-environment \
        | ${pkgs.gnused}/bin/sed -n 's/^NIRI_SOCKET=//p')
      if test -n "$NIRI_SOCKET"; then
        export NIRI_SOCKET
        exec ${sleepyctl} bindings reconcile --online-required
      fi
      attempt=$((attempt + 1))
      ${pkgs.coreutils}/bin/sleep 0.1
    done
    echo "Sleepy online binding reconciliation timed out waiting for NIRI_SOCKET" >&2
    exit 1
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

    home.activation.sleepyBindings = lib.hm.dag.entryAfter ["writeBoundary"] ''
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
        ExecStart = "${pkgs.gammastep}/bin/gammastep -m wayland -O 4500";
        Restart = "on-failure";
      };
    };
  };
}
