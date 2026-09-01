{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.sleepy.enable {
    systemd.user.services.sleepy-shell = {
      Unit = {
        Description = "Sleepy desktop shell";
        PartOf = ["graphical-session.target"];
        Requisite = ["graphical-session.target"];
        Wants = ["sleepy-session.service"];
        After = ["sleepy-session.service"];
        StartLimitIntervalSec = 30;
        StartLimitBurst = 3;
      };
      Service = {
        Type = "simple";
        ExecStart = "${config.sleepy.shellPackage}/bin/sleepy-shell";
        Environment = ["QML_XHR_ALLOW_FILE_READ=1"];
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = ["graphical-session.target"];
    };
  };
}
