{
  inputs,
  source,
  ...
}: {
  lib,
  pkgs,
  modulesPath,
  ...
}: {
  imports = [
    (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix")
    ../../modules/nixos/options.nix
    ../../modules/nixos/branding
  ];
  nixpkgs.overlays = [inputs.self.overlays.default];
  documentation = {
    enable = false;
    man.enable = false;
    nixos.enable = false;
  };
  boot = {
    zfs.forceImportRoot = false;
    kernelParams = ["quiet" "loglevel=3" "rd.systemd.show_status=false" "systemd.show_status=false"];
  };
  console = {
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v24n.psf.gz";
  };
  services.openssh.enable = lib.mkForce false;
  networking = {
    hostName = "sleepy-live";
    networkmanager.enable = true;
    wireless.enable = lib.mkForce false;
  };
  nix.settings.experimental-features = ["nix-command" "flakes"];
  nix.registry.nixpkgs.flake = inputs.nixpkgs;
  environment = {
    systemPackages = [pkgs.sleepy-installer pkgs.snug pkgs.networkmanager];
    etc = {
      "sleepy-source".source = source;
      "sleepy-guide.md".source = ../../docs/snug.md;
    };
    variables.SLEEPY_SOURCE = "${source}";
  };
  services.getty.helpLine = ''
    Sleepy Linux — terminal installer
    Run sleepy-install to begin; nmtui configures networking.
    sleepy-install --demo previews onboarding without disk changes.
  '';
  # Give tty1 directly to the onboarding UI. Recovery shells remain on other TTYs.
  systemd.services."getty@tty1".enable = false;
  systemd.services.sleepy-installer = {
    description = "Sleepy Linux onboarding";
    wantedBy = ["multi-user.target"];
    after = ["systemd-user-sessions.service" "NetworkManager.service"];
    conflicts = ["getty@tty1.service"];
    environment = {
      TERM = "linux";
      SLEEPY_SOURCE = "${source}";
    };
    serviceConfig = {
      ExecStart = "${pkgs.sleepy-installer}/bin/sleepy-install";
      StandardInput = "tty";
      StandardOutput = "tty";
      StandardError = "tty";
      TTYPath = "/dev/tty1";
      TTYReset = true;
      TTYVHangup = true;
      Restart = "always";
      RestartSec = 3;
    };
  };
  image.baseName = lib.mkForce "sleepylinux";
  isoImage = {
    makeEfiBootable = true;
    makeUsbBootable = true;
    # Avoid firmware-dependent GRUB graphics; onboarding owns the visual interface.
    forceTextMode = true;
  };
  system.stateVersion = "26.05";
}
