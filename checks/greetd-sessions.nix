{
  config,
  pkgs,
}: let
  python = pkgs.python3.withPackages (p: [p.pydbus p.dbus-python p.pyxdg]);
in
  assert pkgs.lib.assertMsg
  (pkgs.lib.hasPrefix "${config.services.displayManager.sessionData.desktops}/share"
    config.environment.sessionVariables.XDG_DATA_DIRS)
  "The filtered login entries must precede the compositor package in XDG_DATA_DIRS";
    pkgs.runCommand "sleepy-greetd-sessions" {
      nativeBuildInputs = [config.programs.hyprland.package config.programs.uwsm.package];
      PYTHONPATH = "${config.programs.uwsm.package}/share/uwsm/modules";
    } ''
      ${python}/bin/python3 ${./greetd-sessions.py} ${config.services.displayManager.sessionData.desktops}
      touch "$out"
    ''
