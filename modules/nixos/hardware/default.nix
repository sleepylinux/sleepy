{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.sleepy;
in {
  options.sleepy = {
    hardware.nvidia.enable = lib.mkEnableOption "NVIDIA open kernel driver (Turing and newer)";
    features = {
      bluetooth.enable = lib.mkEnableOption "Bluetooth radio support";
      gaming.enable = lib.mkEnableOption "Steam, GameMode, Gamescope and MangoHud";
      development.enable = lib.mkEnableOption "Git and project-scoped direnv development environments";
      flatpak.enable = lib.mkEnableOption "Flatpak desktop applications";
    };
  };

  config = lib.mkMerge [
    {
      hardware.bluetooth.enable = lib.mkDefault cfg.features.bluetooth.enable;
      hardware.graphics.enable = true;
      nix.settings.experimental-features = ["nix-command" "flakes"];
    }
    (lib.mkIf cfg.hardware.nvidia.enable {
      nixpkgs.config.allowUnfree = true;
      services.xserver.videoDrivers = ["nvidia"];
      hardware.nvidia = {
        open = true;
        modesetting.enable = true;
        nvidiaSettings = true;
      };
    })
    (lib.mkIf cfg.features.gaming.enable {
      nixpkgs.config.allowUnfree = true;
      hardware.graphics.enable32Bit = true;
      programs = {
        steam.enable = true;
        gamemode.enable = true;
        gamescope.enable = true;
      };
      environment.systemPackages = [pkgs.mangohud];
    })
    (lib.mkIf cfg.features.development.enable {
      programs.git.enable = true;
      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
      };
    })
    (lib.mkIf cfg.features.flatpak.enable {
      services.flatpak.enable = true;
      environment.systemPackages = [pkgs.gnome-software];
      systemd.services.sleepy-flathub = {
        description = "Configure the selected Flathub application source";
        wantedBy = ["multi-user.target"];
        wants = ["network-online.target"];
        after = ["network-online.target"];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pkgs.flatpak}/bin/flatpak remote-add --system --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo";
        };
      };
    })
  ];
}
