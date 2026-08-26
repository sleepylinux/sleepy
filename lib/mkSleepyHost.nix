{inputs}: {
  system,
  hostName,
  primaryUser,
  sleepyVersion,
  hardwareModule,
  extraModules ? [],
}:
inputs.nixpkgs.lib.nixosSystem {
  inherit system;

  specialArgs = {
    inherit inputs primaryUser;
  };

  modules =
    [
      hardwareModule
      ../profiles/desktop.nix
      inputs.home-manager.nixosModules.home-manager
      {
        networking.hostName = hostName;
        sleepy = {
          inherit primaryUser;
          version = sleepyVersion;
        };
      }
    ]
    ++ extraModules;
}
