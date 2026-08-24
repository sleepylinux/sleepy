{inputs}:
final: _prev: let
  system = final.stdenv.hostPlatform.system;
  sdkPackages = inputs.sleepy-sdk.packages.${system};
  sessionPackages = inputs.sleepy-session.packages.${system};
  artworkPackages = inputs.sleepy-artwork.packages.${system};
  desktopPackages = inputs.sleepy-desktop.packages.${system};
in {
  sleepy-contract = sdkPackages.sleepy-contract;
  sleepy-session = sessionPackages.sleepy-session;
  sleepy-session-user-unit = sessionPackages.sleepy-session-user-unit;
  sleepy-artwork = artworkPackages.sleepy-artwork;
  sleepy-shell = desktopPackages.sleepy-shell;
  sleepy-settings-preview = desktopPackages.sleepy-settings-preview;

  # Compatibility alias for existing consumers. Ownership is external.
  sleepy-branding = artworkPackages.sleepy-artwork;
}
