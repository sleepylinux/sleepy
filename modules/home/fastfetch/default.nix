{
  config,
  lib,
  ...
}: let
  defaults = builtins.fromJSON (builtins.readFile ./defaults.json);
in {
  config = lib.mkIf config.sleepy.enable {
    programs.fastfetch = {
      enable = lib.mkDefault true;
      # Leaf defaults let hosts replace one detail without dropping the logo,
      # palette or remaining layout. A custom module list replaces this list.
      settings = lib.mapAttrsRecursive (_path: lib.mkDefault) (
        lib.recursiveUpdate defaults {
          logo.source = "${config.sleepy.brandingPackage}/share/sleepy-artwork/branding/fastfetch.txt";
        }
      );
    };
  };
}
