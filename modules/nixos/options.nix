{lib, ...}: {
  options.sleepy = {
    primaryUser = lib.mkOption {
      type = lib.types.str;
      default = "sleepy";
      description = "Primary user configured by the Sleepy desktop module.";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "0.1.0";
      description = "Sleepy release version exposed through os-release.";
    };
  };
}
