{
  config,
  lib,
  ...
}: {
  # Choose your own host name and normal user before installing.
  networking.hostName = "sleepy";
  sleepy.primaryUser = "alice";
  sleepy.hardware.gpu = "auto";

  # UEFI example: mount your EFI system partition at /boot first.
  # For BIOS, replace these with the appropriate GRUB configuration.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Prague";
  services.xserver.xkb.layout = lib.mkForce "us";
  services.xserver.xkb.options = lib.mkForce "";

  # Set a password with nixos-enter + passwd before reboot (see installation.md).
  users.mutableUsers = true;
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${config.sleepy.primaryUser} = {pkgs, ...}: {
      home.stateVersion = "26.05";
      sleepy = {
        enable = true;
        primaryUser = config.sleepy.primaryUser;
        brandingPackage = pkgs.sleepy-artwork;
        lockerPackage = pkgs.sleepy-locker;
        sessionPackage = pkgs.sleepy-session;
        shellPackage = pkgs.sleepy-shell;
      };
    };
  };
  environment.etc."snug/system.json".mode = "0644";
  environment.etc."snug/system.json".text = builtins.toJSON {
    flake = "/etc/nixos";
    host = "sleepy";
    input = "sleepy";
    source = "github:sleepylinux/sleepy";
  };
  # Initial installation compatibility versions; do not bump for rolling updates.
  system.stateVersion = "26.05";
}
