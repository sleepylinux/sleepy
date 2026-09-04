{inputs}: final: _prev: let
  system = final.stdenv.hostPlatform.system;
  sdkPackages = inputs.sleepy-sdk.packages.${system};
  sessionPackages = inputs.sleepy-session.packages.${system};
  artworkPackages = inputs.sleepy-artwork.packages.${system};
  desktopPackages = inputs.sleepy-desktop.packages.${system};
in {
  inherit (sdkPackages) sleepy-contract;
  inherit (sessionPackages) sleepy-session sleepy-session-user-unit;
  inherit (artworkPackages) sleepy-artwork;
  inherit (desktopPackages) sleepy-locker sleepy-settings-preview sleepy-shell;
  sleepy-journal-fault-runner = final.callPackage ../packages/sleepy-journal-fault-runner {
    inherit (sessionPackages) sleepy-session;
  };

  # Compatibility alias for existing consumers. Ownership is external.
  sleepy-branding = artworkPackages.sleepy-artwork;
}
