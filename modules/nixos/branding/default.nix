{config, ...}: {
  system.nixos = {
    distroId = "sleepy";
    distroName = "Sleepy Linux";
    vendorId = "sleepy";
    vendorName = "Sleepy Linux";
    extraOSReleaseArgs = {
      ID_LIKE = "nixos";
      VARIANT = "Sleepy Desktop";
      VARIANT_ID = "sleepy";
      SLEEPY_VERSION = config.sleepy.version;
      LOGO = "sleepy";
    };
  };
}
