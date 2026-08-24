{
  pkgs,
  sessionPackage,
  source,
}:
pkgs.runCommand "sleepy-bindings-contract" {
  nativeBuildInputs = [pkgs.coreutils pkgs.gnugrep pkgs.niri sessionPackage];
} ''
  set -eu
  export HOME="$TMPDIR/home"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_STATE_HOME="$HOME/.local/state"
  export SLEEPY_NIRI_VALIDATOR=${pkgs.niri}/bin/niri
  unset NIRI_SOCKET

  mkdir -p "$XDG_CONFIG_HOME/niri"
  cp ${source}/modules/home/niri/config/*.kdl "$XDG_CONFIG_HOME/niri/"
  ${sessionPackage}/bin/sleepyctl bindings reconcile
  ${sessionPackage}/bin/sleepyctl bindings initialize

  core="$XDG_CONFIG_HOME/niri/bindings-core.kdl"
  generated="$XDG_CONFIG_HOME/niri/sleepy-user-bindings.kdl"
  test -f "$generated"
  test "$(${pkgs.gnugrep}/bin/grep -c '^[[:space:]]*Mod.*{' "$core")" -eq 1
  ${pkgs.gnugrep}/bin/grep -F 'Mod+Shift+Escape' "$core"
  ${pkgs.gnugrep}/bin/grep -F 'quickshell" "ipc" "--config" "sleepy" "call" "sleepy" "toggleControlCenter' "$generated"
  ${pkgs.gnugrep}/bin/grep -F 'openPowerMenu' "$generated"
  ${pkgs.gnugrep}/bin/grep -F 'requestSessionAction' "$generated"
  ! ${pkgs.gnugrep}/bin/grep -E 'systemctl|poweroff|reboot|niri.*quit' "$generated"
  ${pkgs.niri}/bin/niri validate --config "$XDG_CONFIG_HOME/niri/config.kdl"
  touch "$out"
''
