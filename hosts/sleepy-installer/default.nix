{
  lib,
  modulesPath,
  pkgs,
  ...
}: {
  imports = [(modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")];

  system.stateVersion = "26.05";
  environment.etc."sleepy-installer-image".text = "Sleepy installer 0.1.0-alpha\n";
  environment.extraOutputsToInstall = lib.mkForce [];
  networking = {
    hostName = "sleepy-installer";
    networkmanager.enable = true;
    wireless.enable = lib.mkForce false;
  };
  services.openssh.enable = lib.mkForce false;
  # The installer only needs a firmware framebuffer and network access. Full
  # desktop/GPU firmware is still selected by the installed hardware profile.
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.wirelessRegulatoryDatabase = true;
  hardware.firmware = [
    (import ../../packages/vendor/installer-network-firmware {inherit pkgs;})
    pkgs.ipw2200-firmware
    pkgs.rtl8192su-firmware
    pkgs.zd1211fw
  ];
  boot.blacklistedKernelModules = ["amdgpu" "radeon" "nouveau" "nvidia" "i915" "xe"];
  services.getty.helpLine = lib.mkForce "Sleepy installation and recovery · run sleepy-install";
  programs.bash.interactiveShellInit = ''
    if [ "$(tty)" = /dev/tty1 ] && [ -z "''${SLEEPY_INSTALLER_STARTED:-}" ]; then
      export SLEEPY_INSTALLER_STARTED=1
      sleepy-install
    fi
  '';
  nix.settings.experimental-features = ["nix-command" "flakes"];
  isoImage = {
    volumeID = "SLEEPY_INSTALL";
    squashfsCompression = "zstd -Xcompression-level 15";
  };
  image.baseName = lib.mkForce "sleepy-0.1.0-alpha-x86_64-linux";
  boot.supportedFilesystems = lib.mkForce ["btrfs" "vfat" "ext4"];
  boot.kernelParams = ["console=tty0" "console=ttyS0,115200n8"];
  documentation = {
    enable = lib.mkForce false;
    nixos.enable = lib.mkForce false;
    man.enable = lib.mkForce false;
    doc.enable = lib.mkForce false;
    info.enable = lib.mkForce false;
  };
}
