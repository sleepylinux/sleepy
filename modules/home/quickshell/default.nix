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
      configs.sleepy = "${config.sleepy.shellPackage}/share/quickshell/sleepy";
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
        StartLimitIntervalSec = 30;
        StartLimitBurst = 3;
      };
      Service.RestartSec = 2;
    };
  };
}
