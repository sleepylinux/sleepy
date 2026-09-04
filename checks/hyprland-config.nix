{
  homeConfig,
  pkgs,
}: let
  managedConfig = homeConfig.xdg.configFile."hypr/hyprland.conf".source;
  expectedVersion = "0.56.2";
in
  assert pkgs.lib.assertMsg
  (pkgs.hyprland.version == expectedVersion)
  "Sleepy legacy .conf validation is locked to Hyprland ${expectedVersion}";
    pkgs.runCommand "sleepy-hyprland-config" {
      nativeBuildInputs = [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.gnused
        pkgs.hyprland
      ];
    } ''
      set -eu

      config="$TMPDIR/hyprland.conf"
      runtime_dir="$TMPDIR/runtime"
      install -d -m 0700 "$runtime_dir"
      export XDG_RUNTIME_DIR="$runtime_dir"
      cp ${managedConfig} "$config"

      # The mutable per-user include is deliberately outside the Nix store.
      # Validation removes only that source line; the generated policy itself
      # is checked byte-for-byte as Home Manager will install it.
      sed -i '\|^[[:space:]]*source = .*/hypr/sleepy-user.conf[[:space:]]*$|d' "$config"

      ! grep -E 'workspace_swipe|windowrule(v2)?[[:space:]]*=[[:space:]]*(float|pin),|suppressevent|layerrule[[:space:]]*=[[:space:]]*(blur|ignorealpha),' "$config"
      ${pkgs.hyprland}/bin/Hyprland --verify-config --config "$config"
      test -s "$config"
      cp "$config" "$out"
    ''
