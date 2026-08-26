{
  mkSleepyHost,
  primaryUser,
  sleepyVersion,
}: let
  baseline = import ./baseline.nix;
in
  mkSleepyHost {
    inherit (baseline) system;
    hostName = "sleepy-vm";
    inherit primaryUser sleepyVersion;
    hardwareModule = ./hardware-configuration.nix;
    extraModules = [
      ./boot.nix
      ./ghostty.nix
      ./ssh.nix
      {system.stateVersion = baseline.systemStateVersion;}
    ];
  }
