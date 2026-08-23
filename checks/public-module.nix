{
  nixosModule,
  nixpkgs,
  pkgs,
}: let
  mkSystem = sleepy:
    nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        nixosModule
        {
          inherit sleepy;
          system.stateVersion = "26.05";
        }
      ];
    };
  defaultConfig = (mkSystem {}).config;
  overriddenConfig =
    (mkSystem {
      primaryUser = "sleepy-test";
      version = "9.8.7";
    }).config;
in
  assert defaultConfig.sleepy.primaryUser == "sleepy";
  assert defaultConfig.sleepy.version == "0.1.0";
  assert defaultConfig.users.users.sleepy.isNormalUser;
  assert defaultConfig.system.nixos.extraOSReleaseArgs.SLEEPY_VERSION == "0.1.0";
  assert overriddenConfig.sleepy.primaryUser == "sleepy-test";
  assert overriddenConfig.sleepy.version == "9.8.7";
  assert overriddenConfig.users.users.sleepy-test.isNormalUser;
  assert overriddenConfig.system.nixos.extraOSReleaseArgs.SLEEPY_VERSION == "9.8.7";
    pkgs.runCommand "sleepy-public-module-check" {} ''
      touch "$out"
    ''
