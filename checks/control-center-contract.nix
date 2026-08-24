{
  pkgs,
  shellPackage,
  source,
}:
pkgs.runCommand "sleepy-control-center-contract" {
  nativeBuildInputs = [pkgs.findutils pkgs.gnugrep];
} ''
  set -eu
  desktop=${shellPackage}/share/sleepy-desktop
  test -d "$desktop"
  ${pkgs.gnugrep}/bin/grep -R -F 'ShellId' "$desktop"
  ${pkgs.gnugrep}/bin/grep -R -F 'sleepy' "$desktop"
  ${pkgs.gnugrep}/bin/grep -R -F 'toggleControlCenter' "$desktop"
  ${pkgs.gnugrep}/bin/grep -R -F 'requestSessionAction' "$desktop"
  ${pkgs.gnugrep}/bin/grep -R -F 'openPowerMenu' "$desktop"
  ${pkgs.gnugrep}/bin/grep -F 'configs.sleepy' ${source}/modules/home/quickshell/default.nix
  ${pkgs.gnugrep}/bin/grep -F 'Requires = ["sleepy-bindings-online.service"]' ${source}/modules/home/quickshell/default.nix
  touch "$out"
''
