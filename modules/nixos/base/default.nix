{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.sleepy;
in {
  users.users.${cfg.primaryUser} = {
    isNormalUser = true;
    extraGroups = ["wheel"];
    shell = pkgs.fish;
  };

  networking.networkmanager.enable = true;
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  services.xserver.xkb = {
    layout = lib.mkDefault "us";
    options = lib.mkDefault "";
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
