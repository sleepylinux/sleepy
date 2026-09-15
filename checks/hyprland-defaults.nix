{
  homeConfiguration,
  pkgs,
}: let
  defaultHome = homeConfiguration.config;
  customizedHome =
    (homeConfiguration.extendModules {
      modules = [
        {
          wayland.windowManager.hyprland.settings = {
            "$mod" = "ALT";
            misc = {
              key_press_enables_dpms = false;
              mouse_move_enables_dpms = false;
            };
            input = {
              kb_layout = "de";
              touchpad.natural_scroll = false;
            };
          };
        }
      ];
    }).config;
  defaults = defaultHome.wayland.windowManager.hyprland.settings;
  customized = customizedHome.wayland.windowManager.hyprland.settings;
  validate = homeConfig: pkgs.callPackage ./hyprland-config.nix {inherit homeConfig;};
in
  assert pkgs.lib.assertMsg
  ((defaults."$mod" or null) == "SUPER" && (defaults.input.kb_layout or null) == "us")
  "Sleepy generic Hyprland variables and keyboard must survive module merging";
  assert pkgs.lib.assertMsg
  ((defaults.misc.key_press_enables_dpms or null)
    == true
    && (defaults.misc.mouse_move_enables_dpms or null) == true)
  "Input must wake DPMS independently of the shell idle monitor lifecycle";
  assert pkgs.lib.assertMsg
  ((customized."$mod" or null)
    == "ALT"
    && (customized.input.kb_layout or null) == "de"
    && (customized.input.touchpad.natural_scroll or null) == false
    && (customized.input.touchpad.tap-to-click or null) == true
    && (customized."$terminal" or null) == "ghostty"
    && (customized.misc.key_press_enables_dpms or null) == false
    && (customized.misc.mouse_move_enables_dpms or null) == false
    && (customized.misc.disable_hyprland_logo or null) == true)
  "Hyprland leaf overrides must preserve unrelated and sibling defaults";
    pkgs.runCommand "sleepy-hyprland-defaults" {} ''
      mkdir -p "$out"
      cp ${validate defaultHome} "$out/default.conf"
      cp ${validate customizedHome} "$out/customized.conf"
    ''
