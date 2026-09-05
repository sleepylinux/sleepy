{
  description = "My rolling Sleepy host";
  inputs = {
    sleepy.url = "github:sleepylinux/sleepy";
    nixpkgs.follows = "sleepy/nixpkgs";
    home-manager.follows = "sleepy/home-manager";
  };
  outputs = {
    sleepy,
    nixpkgs,
    home-manager,
    ...
  }: {
    nixosConfigurations.sleepy = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        sleepy.nixosModules.sleepy
        home-manager.nixosModules.home-manager
        ./hardware-configuration.nix
        ./configuration.nix
        {
          nixpkgs.overlays = [sleepy.overlays.default];
          home-manager.sharedModules = [sleepy.homeManagerModules.sleepy];
        }
      ];
    };
  };
}
