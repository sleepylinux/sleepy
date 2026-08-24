{
  config,
  lib,
  ...
}: {
  assertions = [
    {
      assertion = lib.versionAtLeast config.programs.niri.package.version "26.04";
      message = "Sleepy requires Niri 26.04 or newer for optional includes and confirmed reloads";
    }
  ];
}
