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
        services.xserver.xkb = {
          layout = "us,ru";
          options = "grp:alt_shift_toggle";
        };
        sleepy.features.bluetooth.enable = true;
        sleepy.features.development.enable = true;
        services.qemuGuest.enable = true;
        system.stateVersion = baseline.systemStateVersion;
      }
    ];
  }
