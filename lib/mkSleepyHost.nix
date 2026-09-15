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
      ({config, ...}: {
        networking.hostName = hostName;
        sleepy = {
          inherit primaryUser;
          version = "0.1.0";
        };
        # Keep the evaluated source in each generation's closure. Rollback then
        # restores both the running system and the source used for saved rebuilds.
        environment.etc."sleepy/source.json".text = builtins.toJSON {
          schema = 1;
          source_path = inputs.self.outPath;
          nar_hash = inputs.self.narHash;
          revision = inputs.self.rev or null;
          version = config.sleepy.version;
        };
      })
    ]
    ++ extraModules;
}
