{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf (config.sleepy.enable && (config.sleepy.sessionPackage != null || config.sleepy.lockerPackage != null)) {
    # Session and locker share private socket paths, but neither owns the other
    # process's lifetime. Keep their directory while either service needs it.
    # The last client stopping releases this owner, which removes the directory
    # after both clients have stopped (including graphical-session shutdown).
    systemd.user.services.sleepy-runtime = {
      Unit = {
        Description = "Sleepy shared private runtime directory";
        PartOf = ["graphical-session.target"];
        After = ["graphical-session.target"];
        Before = ["sleepy-session.service" "sleepy-locker.service"];
        StopWhenUnneeded = true;
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/true";
        RuntimeDirectory = "sleepy";
        RuntimeDirectoryMode = "0700";
      };
    };
  };
}
