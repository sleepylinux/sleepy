{
  lib,
  modulesPath,
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
  image.fileName = "sleepy-0.1.0-alpha-x86_64-linux.iso";
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
