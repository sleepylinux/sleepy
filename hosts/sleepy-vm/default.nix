{mkSleepyHost}: let
  baseline = import ./baseline.nix;
in
  mkSleepyHost {
    inherit (baseline) system;
    hostName = "sleepy-vm";
    primaryUser = "lazy";
    hardwareModule = ./hardware-configuration.nix;
    extraModules = [
      ./boot.nix
      ./ghostty.nix
      ./ssh.nix
      {
        services.qemuGuest.enable = true;
        system.stateVersion = baseline.systemStateVersion;
      }
    ];
  }
