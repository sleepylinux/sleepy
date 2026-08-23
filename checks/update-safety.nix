{
  activationPackage,
  pkgs,
}:
pkgs.runCommand "sleepy-update-safety-check" {
  nativeBuildInputs = [pkgs.ripgrep];
} ''
  set -eu

  home_files=${activationPackage}/home-files
  settings_file="$home_files/.config/sleepy/settings.json"
  niri_dir="$home_files/.config/niri"

  if [ -e "$settings_file" ] || [ -L "$settings_file" ]; then
    echo "Home Manager must not manage .config/sleepy/settings.json" >&2
    exit 1
  fi

  if ${pkgs.ripgrep}/bin/rg -n --glob '*.nix' \
    'settings\.json|force[[:space:]]*=[[:space:]]*true[[:space:]]*;' \
    ${../modules/home} ${../flake.nix}; then
    echo "Home Manager sources must not reference mutable settings or force file ownership" >&2
    exit 1
  fi

  if [ ! -d "$niri_dir" ]; then
    echo "standalone activation has no managed Niri directory" >&2
    exit 1
  fi

  niri_count=0
  for managed_file in "$niri_dir"/*.kdl; do
    if [ ! -L "$managed_file" ]; then
      echo "managed Niri file is missing or is not a Home Manager link: $managed_file" >&2
      exit 1
    fi

    target=$(${pkgs.coreutils}/bin/readlink -f "$managed_file")
    case "$target" in
      /nix/store/*) ;;
      *)
        echo "managed Niri file does not resolve into the Nix store: $managed_file -> $target" >&2
        exit 1
        ;;
    esac

    if [ ! -f "$target" ] || [ -w "$target" ]; then
      echo "managed Niri target is missing or writable: $target" >&2
      exit 1
    fi

    permissions=$(${pkgs.coreutils}/bin/stat -c '%A' "$target")
    case "$permissions" in
      *w*)
        echo "managed Niri target has a write bit: $permissions $target" >&2
        exit 1
        ;;
    esac

    niri_count=$((niri_count + 1))
  done

  if [ "$niri_count" -ne 6 ]; then
    echo "expected exactly six immutable managed Niri KDL files, found $niri_count" >&2
    exit 1
  fi

  for expected_file in config input appearance bindings rules startup; do
    if [ ! -L "$niri_dir/$expected_file.kdl" ]; then
      echo "missing managed Niri file: $expected_file.kdl" >&2
      exit 1
    fi
  done

  touch "$out"
''
