{
  config,
  lib,
  ...
}: {
  config = lib.mkIf (config.sleepy.enable && config.sleepy.sessionPackage != null) {
    home.packages = [config.sleepy.sessionPackage];

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
  };
}
