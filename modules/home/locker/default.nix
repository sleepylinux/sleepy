{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.sleepy.enable && config.sleepy.lockerPackage != null) {
    systemd.user.services = {
      sleepy-locker = {
        Unit = {
          Description = "Sleepy fail-secure session locker";
          PartOf = ["graphical-session.target"];
          After = ["graphical-session.target"];
          Requisite = ["graphical-session.target"];
          OnFailure = ["sleepy-locker-failsafe.service"];
        };

        Service = {
          Type = "simple";
          ExecStart = "${config.sleepy.lockerPackage}/bin/sleepy-locker";
          Environment = [
            "SLEEPY_LOCKER_PAM_SERVICE=sleepy-locker"
            "SLEEPY_LOCKER_SOCKET=%t/sleepy/locker.sock"
          ];
          KillMode = "control-group";
          Restart = "no";
          RuntimeDirectory = "sleepy";
          RuntimeDirectoryMode = "0700";
          UMask = "0077";
        };

        Install.WantedBy = ["graphical-session.target"];
      };

      sleepy-locker-failsafe = {
        Unit.Description = "Terminate the Sleepy graphical session after locker failure";
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.uwsm}/bin/uwsm stop";
          TimeoutStartSec = 15;
        };
      };
    };
  };
}
