{pkgs}:
pkgs.runCommand "niri-config-check" {} ''
  config="$TMPDIR/config"
  cp -R ${../modules/home/niri/config} "$config"
  chmod -R u+w "$config"
  ${pkgs.niri}/bin/niri validate --config "$config/config.kdl"
  touch "$out"
''
