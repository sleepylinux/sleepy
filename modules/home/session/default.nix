{
  config,
  lib,
  pkgs,
  ...
}: let
  sessionRuntimePackages = with pkgs; [
    config.sleepy.sessionPackage
    networkmanager
    bluez
    wireplumber
    pipewire
    brightnessctl
    ddcutil
    lm_sensors
    libqalculate
    power-profiles-daemon
    upower
    playerctl
    gammastep
    cliphist
    wl-clipboard
    swappy
    systemd
    curl
  ];
  sessionRuntimePath = lib.makeBinPath sessionRuntimePackages;
in {
  config = lib.mkIf (config.sleepy.enable && config.sleepy.sessionPackage != null) {
    home.packages = sessionRuntimePackages;

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
          StartLimitIntervalSec = 30;
          StartLimitBurst = 5;
        };

        Service = {
          Type = "notify";
          NotifyAccess = "main";
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

      sleepy-clipboard = {
        Unit = {
          Description = "Sleepy clipboard history watcher";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
          Requisite = ["graphical-session.target"];
        };
        Service = {
          Type = "simple";
          ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type text --watch ${pkgs.cliphist}/bin/cliphist store";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = ["graphical-session.target"];
      };

      gammastep = {
        Unit = {
          Description = "Sleepy managed night-light provider";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
          Requisite = ["graphical-session.target"];
        };
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
