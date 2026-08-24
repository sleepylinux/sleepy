{
  config,
  pkgs,
  ...
}: let
  cfg = config.sleepy;
in {
  imports = [./niri-version.nix];
  users.users.${cfg.primaryUser} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;
  };

  networking.networkmanager.enable = true;
  hardware.bluetooth.enable = true;

  i18n.defaultLocale = "en_US.UTF-8";
  services.xserver.xkb = {
    layout = "us,ru";
    options = "grp:alt_shift_toggle";
  };

  programs = {
    dconf.enable = true;
    fish.enable = true;
  };

  security = {
    polkit.enable = true;
    rtkit.enable = true;
  };

  services = {
    pipewire = {
      enable = true;
      alsa.enable = true;
      pulse.enable = true;
    };
    upower.enable = true;
    power-profiles-daemon.enable = true;
  };
}
