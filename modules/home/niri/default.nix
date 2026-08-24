{
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.sleepy.enable {
    xdg.configFile = {
      "niri/config.kdl".source = ./config/config.kdl;
      "niri/input.kdl".source = ./config/input.kdl;
      "niri/appearance.kdl".source = ./config/appearance.kdl;
      "niri/bindings-core.kdl".source = ./config/bindings-core.kdl;
      "niri/rules.kdl".source = ./config/rules.kdl;
      "niri/startup.kdl".source = ./config/startup.kdl;
    };
  };
}
