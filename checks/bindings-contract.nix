{
  pkgs,
  sessionPackage,
  source,
}:
pkgs.runCommand "sleepy-bindings-contract" {
  nativeBuildInputs = [pkgs.coreutils pkgs.gawk pkgs.gnugrep pkgs.niri sessionPackage];
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
  ${pkgs.bash}/bin/bash ${./bindings-policy.sh} "$core" "$generated"

  for required in \
    'spawn "ghostty"' \
    'spawn "fuzzel"' \
    'close-window;' \
    'focus-column-left;' \
    'focus-column-right;' \
    'focus-window-up;' \
    'focus-window-down;' \
    'focus-workspace-previous;' \
    'focus-workspace-next;' \
    '"toggleControlCenter"' \
    '"requestSessionAction" "lock"' \
    '"requestSessionAction" "logout"' \
    '"requestSessionAction" "reboot"' \
    '"requestSessionAction" "powerOff"' \
    '"openPowerMenu"' \
    'spawn "playerctl" "play-pause"' \
    'spawn "playerctl" "next"' \
    'spawn "playerctl" "previous"' \
    'spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"' \
    'spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"' \
    'spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"' \
    'spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"' \
    'spawn "brightnessctl" "set" "5%+"' \
    'spawn "brightnessctl" "set" "5%-"'; do
    ${pkgs.gnugrep}/bin/grep -F -- "$required" "$generated"
  done
  ${pkgs.gnugrep}/bin/grep -F 'spawn "quickshell" "ipc" "--config" "sleepy" "call" "sleepy" "toggleControlCenter"' "$generated"
  ${pkgs.niri}/bin/niri validate --config "$XDG_CONFIG_HOME/niri/config.kdl"
  touch "$out"
''
