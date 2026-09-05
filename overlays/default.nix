{inputs}: final: _prev: let
  system = final.stdenv.hostPlatform.system;
  sdkPackages = inputs.sleepy-sdk.packages.${system};
  sessionPackages = inputs.sleepy-session.packages.${system};
  artworkPackages = inputs.sleepy-artwork.packages.${system};
  desktopPackages = inputs.sleepy-desktop.packages.${system};
in {
  hyprland = _prev.hyprland.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../patches/hyprland-session-lock-vt-focus.patch];
  });
  snug = final.callPackage ../packages/snug {};
  sleepy-installer = final.callPackage ../packages/sleepy-installer {};
  inherit (sdkPackages) sleepy-contract;
  inherit (sessionPackages) sleepy-session-user-unit;
  sleepy-session = sessionPackages.sleepy-session.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../patches/session-bounded-audio-refresh.patch];
    passthru =
      (old.passthru or {})
      // {
        sleepyUpstreamPackage = sessionPackages.sleepy-session;
        sleepyDownstreamPatches = [../patches/session-bounded-audio-refresh.patch];
      };
  });
  inherit (artworkPackages) sleepy-artwork;
  sleepy-locker = desktopPackages.sleepy-locker.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../patches/locker-supported-unlock.patch];
    passthru =
      (old.passthru or {})
      // {
        sleepyUpstreamPackage = desktopPackages.sleepy-locker;
        sleepyDownstreamPatches = [../patches/locker-supported-unlock.patch];
      };
  });
  sleepy-shell = desktopPackages.sleepy-shell.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../patches/desktop-bounded-nmcli.patch];
    passthru =
      (old.passthru or {})
      // {
        sleepyUpstreamPackage = desktopPackages.sleepy-shell;
        sleepyDownstreamPatches = [../patches/desktop-bounded-nmcli.patch];
      };
  });
  sleepy-settings-preview = desktopPackages.sleepy-settings-preview.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../patches/desktop-bounded-nmcli.patch];
    passthru =
      (old.passthru or {})
      // {
        sleepyUpstreamPackage = desktopPackages.sleepy-settings-preview;
        sleepyDownstreamPatches = [../patches/desktop-bounded-nmcli.patch];
      };
  });
  sleepy-journal-fault-runner = final.callPackage ../packages/sleepy-journal-fault-runner {
    inherit (final) sleepy-session;
  };

  # Compatibility alias for existing consumers. Ownership is external.
  sleepy-branding = artworkPackages.sleepy-artwork;
}
