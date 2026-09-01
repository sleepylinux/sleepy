{
  activationPackage,
  baselineActivationPackage,
  pkgs,
}:
pkgs.runCommand "sleepy-update-safety-check" {
  nativeBuildInputs = [pkgs.ripgrep];
} ''
  set -eu

  home_files=${activationPackage}/home-files
  baseline_home_files=${baselineActivationPackage}/home-files
  hyprland_config="$home_files/.config/hypr/hyprland.conf"
  uwsm_env="$home_files/.config/uwsm/env"

  ${pkgs.bash}/bin/bash ${./update-safety-contract.sh} \
    "$home_files" ${activationPackage}/activate \
    ${../modules/home} ${../flake.nix}

  test -d "$baseline_home_files/.config/niri"
  test ! -e "$home_files/.config/niri"
  test ! -L "$home_files/.config/niri"

  for managed_file in "$hyprland_config" "$uwsm_env"; do
    if [ ! -L "$managed_file" ]; then
      echo "candidate Home Manager file is missing or not immutable: $managed_file" >&2
      exit 1
    fi

    target=$(${pkgs.coreutils}/bin/readlink -f "$managed_file")
    case "$target" in
      /nix/store/*) ;;
      *)
        echo "candidate Home Manager file escapes the Nix store: $managed_file -> $target" >&2
        exit 1
        ;;
    esac
    test -f "$target"
  done

  test ! -e "$home_files/.config/hypr/sleepy-user.conf"
  test ! -L "$home_files/.config/hypr/sleepy-user.conf"

  if ${pkgs.ripgrep}/bin/rg -n 'NIRI_SOCKET|SLEEPY_NIRI|/niri/' ${activationPackage}/activate; then
    echo "the candidate activation still reads or mutates Niri state" >&2
    exit 1
  fi

  touch "$out"
''
