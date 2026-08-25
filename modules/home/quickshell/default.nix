{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.sleepy.enable {
    programs.quickshell = {
      enable = true;
      package = pkgs.quickshell;
      configs.sleepy = "${config.sleepy.shellPackage}/share/sleepy-desktop";
      activeConfig = "sleepy";
      systemd = {
        enable = true;
        target = "graphical-session.target";
      };
    };

    systemd.user.services.quickshell = {
      Unit = {
        PartOf = ["graphical-session.target"];
        Requisite = ["graphical-session.target"];
        Requires = ["sleepy-session.service" "sleepy-bindings-online.service"];
        After = ["sleepy-session.service" "sleepy-bindings-online.service"];
        StartLimitIntervalSec = 30;
        StartLimitBurst = 3;
      };
      Service = {
        Environment = ["QML_XHR_ALLOW_FILE_READ=1"];
        RestartSec = 2;
      };
    };
  };
}
