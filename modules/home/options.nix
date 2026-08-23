{lib, ...}: {
  options.sleepy = {
    enable = lib.mkEnableOption "the Sleepy Linux desktop";
    primaryUser = lib.mkOption {type = lib.types.str;};
    brandingPackage = lib.mkOption {type = lib.types.package;};
    shellPackage = lib.mkOption {type = lib.types.package;};
  };
}
