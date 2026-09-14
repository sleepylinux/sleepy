{
  inputs,
  primaryUser,
  config,
  ...
}: {
  imports = [../modules/nixos];

  nixpkgs.overlays = [inputs.self.overlays.default];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${primaryUser} = {pkgs, ...}: {
      imports = [../modules/home];

      home.stateVersion = "26.05";

      wayland.windowManager.hyprland.settings.input = {
        kb_layout = config.services.xserver.xkb.layout;
        kb_options = config.services.xserver.xkb.options;
      };

      sleepy = {
        enable = true;
        inherit primaryUser;
        brandingPackage = pkgs.sleepy-artwork;
        lockerPackage = pkgs.sleepy-locker;
        sessionPackage = pkgs.sleepy-session;
        shellPackage = pkgs.sleepy-shell;
      };
    };
  };
}
