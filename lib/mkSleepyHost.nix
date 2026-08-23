{inputs}: {
  system,
  hostName,
  primaryUser,
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
          version = "0.1.0";
        };
      }
    ]
    ++ extraModules;
}
