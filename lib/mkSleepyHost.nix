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
      ({
        config,
        pkgs,
        ...
      }: let
        # Relative flake inputs have neither narHash nor their own store root.
        # Copy only this source subtree into an immutable, independently rooted
        # input. Hash it at build time, without import-from-derivation evaluation.
        source = builtins.path {
          path = inputs.self.outPath;
          name = "source";
        };
        metadata = pkgs.writeText "sleepy-source-metadata.json" (builtins.toJSON {
          schema = 1;
          source_path = source;
          revision = inputs.self.rev or null;
          version = config.sleepy.version;
        });
      in {
        networking.hostName = hostName;
        sleepy = {
          inherit primaryUser;
          version = "0.1.0";
        };
        # Keep the evaluated source in each generation's closure. Rollback then
        # restores both the running system and the source used for saved rebuilds.
        environment.etc."sleepy/source.json".source =
          pkgs.runCommand "sleepy-source.json" {
            nativeBuildInputs = [config.nix.package pkgs.jq];
          } ''
            digest=$(nix --extra-experimental-features nix-command hash path ${source})
            jq --arg digest "$digest" '. + {nar_hash: $digest}' ${metadata} > "$out"
          '';
      })
    ]
    ++ extraModules;
}
