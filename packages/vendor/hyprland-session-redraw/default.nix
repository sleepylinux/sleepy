{
  pkgs,
  package ? pkgs.hyprland,
}:
assert package.version == "0.56.2";
  package.overrideAttrs (old: {
    patches = (old.patches or []) ++ [./session-activation-redraw.patch];
  })
