{lib, ...}: {
  options.sleepy = {
    enable = lib.mkEnableOption "the Sleepy Linux desktop";
    primaryUser = lib.mkOption {type = lib.types.str;};
    brandingPackage = lib.mkOption {type = lib.types.package;};
    sessionPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional sleepy-session package used by the graphical user service.";
    };
    lockerPackage = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional fail-secure Sleepy locker package.";
    };
    shellPackage = lib.mkOption {type = lib.types.package;};
    capture.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable the asynchronous screenshot API with interactive region consent.";
    };
  };
}
