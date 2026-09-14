{
  inputs,
  system,
}: let
  baseline = inputs.sleepy-m2-baseline;
  # Preserve the migration baseline's production sources and dependencies.
  # Only its cancellation test fixture needs the concurrent-exec repair.
  sessionPackage = baseline.packages.${system}.sleepy-session.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../checks/session-m2-etxtbsy.patch];
  });
  desktopInput = baseline.inputs.sleepy-desktop;
  # The old shell wrapper embeds a session path independently of Home Manager.
  # Re-evaluate it with the same inputs, substituting only the tested baseline.
  desktop = (import (desktopInput.outPath + "/flake.nix")).outputs (desktopInput.inputs
    // {
      self = desktopInput;
      sleepy-session = {
        packages.${system}.sleepy-session = sessionPackage;
      };
    });
  home = baseline.homeConfigurations."lazy@sleepy-vm".extendModules {
    modules = [
      ({lib, ...}: {
        sleepy.sessionPackage = lib.mkForce sessionPackage;
        sleepy.shellPackage = lib.mkForce desktop.packages.${system}.sleepy-shell;
      })
    ];
  };
in {
  inherit sessionPackage;
  activationPackage = home.activationPackage;
}
