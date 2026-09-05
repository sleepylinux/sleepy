{
  config,
  lib,
  pkgs,
  ...
}: {
  config = lib.mkIf config.sleepy.enable {
    home = {
      packages = [(pkgs.callPackage ../../../packages/snug {})];
      sessionPath = ["${config.xdg.stateHome}/snug/profile/bin"];
      activation.snugDesktopEntries = lib.hm.dag.entryAfter ["linkGeneration"] ''
        XDG_DATA_HOME=${lib.escapeShellArg config.xdg.dataHome} \
          ${pkgs.python3}/bin/python3 ${../../../packages/snug/desktop_entries.py} \
          ${lib.escapeShellArg "${config.xdg.stateHome}/snug/profile"}
      '';
    };
    xdg.systemDirs.data = [
      "${config.xdg.dataHome}/snug"
      "${config.xdg.stateHome}/snug/profile/share"
    ];
  };
}
