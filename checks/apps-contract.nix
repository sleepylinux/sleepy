{
  integratedHomeConfig,
  nixosConfig,
  pkgs,
  standaloneHomeConfig,
}: let
  integratedGhostty = integratedHomeConfig.programs.ghostty.package;
  standaloneGhostty = standaloneHomeConfig.programs.ghostty.package;
  expectedIntegratedTerminal = "${integratedGhostty}/bin/ghostty";
  expectedStandaloneTerminal = "${standaloneGhostty}/bin/ghostty";
in
  assert pkgs.lib.assertMsg
  (integratedGhostty != pkgs.ghostty)
  "Sleepy VM must use its renderer-compatible Ghostty package";
  assert pkgs.lib.assertMsg
  (standaloneGhostty == pkgs.ghostty)
  "standalone Home Manager must keep the unwrapped Ghostty package";
  assert pkgs.lib.assertMsg
  (integratedHomeConfig.programs.fuzzel.settings.main.terminal == expectedIntegratedTerminal)
  "integrated Fuzzel must use the final configured Ghostty package";
  assert pkgs.lib.assertMsg
  (standaloneHomeConfig.programs.fuzzel.settings.main.terminal == expectedStandaloneTerminal)
  "standalone Fuzzel must use the final configured Ghostty package";
  assert pkgs.lib.assertMsg
  (!(integratedHomeConfig.home.sessionVariables ? LIBGL_ALWAYS_SOFTWARE))
  "Home Manager must not export LIBGL_ALWAYS_SOFTWARE at session scope";
  assert pkgs.lib.assertMsg
  (!(standaloneHomeConfig.home.sessionVariables ? LIBGL_ALWAYS_SOFTWARE))
  "standalone Home Manager must not export LIBGL_ALWAYS_SOFTWARE at session scope";
  assert pkgs.lib.assertMsg
  (!(nixosConfig.environment.variables ? LIBGL_ALWAYS_SOFTWARE))
  "NixOS must not export LIBGL_ALWAYS_SOFTWARE globally";
  assert pkgs.lib.assertMsg
  (!(nixosConfig.environment.sessionVariables ? LIBGL_ALWAYS_SOFTWARE))
  "NixOS must not export LIBGL_ALWAYS_SOFTWARE at session scope";
    pkgs.runCommand "sleepy-apps-contract" {
      nativeBuildInputs = [pkgs.gnugrep];
    } ''
      set -eu

      wrapper=${integratedGhostty}/bin/ghostty
      standalone=${standaloneGhostty}/bin/ghostty

      test -x "$wrapper"
      test ! -L "$wrapper"
      test -x "$standalone"

      ${pkgs.gnugrep}/bin/grep -Fx "export LIBGL_ALWAYS_SOFTWARE='1'" "$wrapper"
      test "$(${pkgs.gnugrep}/bin/grep -c '^export [A-Za-z_][A-Za-z0-9_]*=' "$wrapper")" -eq 1
      ! ${pkgs.gnugrep}/bin/grep -q 'LIBGL_ALWAYS_SOFTWARE' "$standalone"

      wrapped_version=$("$wrapper" --version)
      standalone_version=$("$standalone" --version)
      test "$wrapped_version" = "$standalone_version"

      touch "$out"
    ''
