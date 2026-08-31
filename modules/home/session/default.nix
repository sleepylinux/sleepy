{
  config,
  lib,
  pkgs,
  ...
}: let
  sleepyctl = "${config.sleepy.sessionPackage}/bin/sleepyctl";
  niriBin = "${pkgs.niri}/bin/niri";
  sessionRuntimePackages = with pkgs; [
    config.sleepy.sessionPackage
    networkmanager
    bluez
    wireplumber
    pipewire
    brightnessctl
    power-profiles-daemon
    upower
    playerctl
    gammastep
    swaylock
    niri
    systemd
    curl
  ];
  sessionRuntimePath = lib.makeBinPath sessionRuntimePackages;
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
    home = {
      packages = sessionRuntimePackages ++ [pkgs.quickshell];

      sessionVariables = {
        SLEEPY_NIRI = niriBin;
        SLEEPY_NIRI_VALIDATOR = niriBin;
      };

      activation.sleepyBindings = lib.hm.dag.entryAfter ["linkGeneration"] ''
        export SLEEPY_NIRI=${lib.escapeShellArg niriBin}
        export SLEEPY_NIRI_VALIDATOR=${lib.escapeShellArg niriBin}
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
    };

    systemd.user.services = {
      sleepy-session = {
        Unit = {
          Description = "Sleepy desktop session event service";
          PartOf = ["graphical-session.target"];
          Wants = lib.optionals (config.sleepy.lockerPackage != null) ["sleepy-locker.service"];
          After =
            ["graphical-session.target" "dbus.socket"]
            ++ lib.optionals (config.sleepy.lockerPackage != null) ["sleepy-locker.service"];
          Requisite = ["graphical-session.target"];
          Requires = ["dbus.socket"];
        };

        Service = {
          Type = "simple";
          ExecStart = "${config.sleepy.sessionPackage}/bin/sleepy-sessiond";
          Environment = [
            "PATH=${sessionRuntimePath}"
            "SLEEPY_LOCKER_SOCKET=%t/sleepy/locker.sock"
          ];
          Restart = "on-failure";
          RestartSec = 2;
          RuntimeDirectory = "sleepy";
          RuntimeDirectoryMode = "0700";
          KillSignal = "SIGINT";
          TimeoutStopSec = 20;
        };

        Install.WantedBy = ["graphical-session.target"];
      };

      sleepy-bindings-online = {
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
            "SLEEPY_NIRI=${niriBin}"
            "SLEEPY_NIRI_VALIDATOR=${niriBin}"
          ];
          RemainAfterExit = true;
        };
        Install.WantedBy = ["graphical-session.target"];
      };

      gammastep = {
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
  };
}
