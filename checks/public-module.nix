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
  approvedCandidate = {
    version = "VM fixture";
    revision = "0000000000000000000000000000000000000000";
    nar_hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };
  candidateConfig = (mkSystem {updates.candidates.vm-fixture = approvedCandidate;}).config;
  # A host can select a portal build without leaving a second backend behind.
  portalOverride =
    ((mkSystem {}).extendModules {
      modules = [{programs.hyprland.portalPackage = pkgs.xdg-desktop-portal-hyprland.overrideAttrs (_: {pname = "sleepy-test-portal";});}];
    }).config;
  overriddenConfig =
    (mkSystem {
      primaryUser = "sleepy-test";
      version = "9.8.7";
    }).config;
  selections = {
    base = {};
    bluetooth.features.bluetooth.enable = true;
    flatpak.features.flatpak.enable = true;
    development.features.development.enable = true;
    gaming.features.gaming.enable = true;
    nvidia.hardware.nvidia.enable = true;
    combined = {
      hardware.nvidia.enable = true;
      features = {
        bluetooth.enable = true;
        flatpak.enable = true;
        development.enable = true;
        gaming.enable = true;
      };
    };
  };
  profiles = builtins.mapAttrs (_name: selection: (mkSystem selection).config) selections;
  selected = config: {
    bluetooth = config.hardware.bluetooth.enable;
    flatpak = config.services.flatpak.enable;
    development = config.programs.git.enable && config.programs.direnv.enable && config.programs.direnv.nix-direnv.enable;
    gaming = config.programs.steam.enable && config.programs.gamemode.enable && config.programs.gamescope.enable;
    nvidia = builtins.elem "nvidia" config.services.xserver.videoDrivers;
  };
  expected = name:
    builtins.listToAttrs (map
      (feature: {
        name = feature;
        value = name == feature || name == "combined";
      })
      ["bluetooth" "flatpak" "development" "gaming" "nvidia"]);
  packageNames = config: map pkgs.lib.getName config.environment.systemPackages;
  # These are optional development tools in the global user PATH, not the
  # transitive runtimes required internally by NixOS desktop/system packages.
  globalDevTools = ["nodejs" "python3" "rustc" "cargo" "go" "jdk" "gcc-wrapper"];
  bluetoothOverride = selection: enabled:
    ((mkSystem selection).extendModules {
      modules = [{hardware.bluetooth.enable = enabled;}];
    }).config.hardware.bluetooth.enable;
in
  assert pkgs.lib.all
  (name:
    pkgs.lib.assertMsg
    (selected profiles.${name} == expected name)
    "Sleepy hardware profile composition failed: ${name}")
  (builtins.attrNames profiles);
  assert pkgs.lib.all
  (name: let
    profile = profiles.${name};
    names = packageNames profile;
    gaming = name == "gaming" || name == "combined";
    nvidia = name == "nvidia" || name == "combined";
    development = name == "development" || name == "combined";
    flatpak = name == "flatpak" || name == "combined";
  in
    pkgs.lib.assertMsg
    (profile.hardware.graphics.enable32Bit
      == gaming
      && profile.programs.git.enable == development
      && profile.programs.direnv.enable == development
      && profile.programs.steam.enable == gaming
      && profile.programs.gamemode.enable == gaming
      && profile.programs.gamescope.enable == gaming
      && builtins.elem "mangohud" names == gaming
      && builtins.elem "steam" names == gaming
      && builtins.elem "git" names == development
      && builtins.elem "direnv" names == development
      && builtins.elem "nvidia-x11" names == nvidia
      && (profile.systemd.timers ? sleepy-flathub) == flatpak
      && builtins.elem "gnome-software" names == flatpak
      && pkgs.lib.intersectLists globalDevTools names == [])
    "Sleepy hardware profile package/default boundary failed: ${name}")
  (builtins.attrNames profiles);
  assert profiles.nvidia.hardware.nvidia.open;
  assert profiles.nvidia.hardware.nvidia.modesetting.enable;
  assert profiles.combined.hardware.nvidia.open;
  assert bluetoothOverride {} true;
  assert !(bluetoothOverride {features.bluetooth.enable = true;} false);
  assert pkgs.lib.all (config:
    builtins.filter (portal: builtins.elem (pkgs.lib.getName portal) ["xdg-desktop-portal-hyprland" "sleepy-test-portal"]) config.xdg.portal.extraPortals
    == [config.programs.hyprland.portalPackage]) [defaultConfig profiles.flatpak portalOverride];
  assert defaultConfig.sleepy.primaryUser == "sleepy";
  assert defaultConfig.sleepy.updates.candidates == {};
  assert !(defaultConfig.environment.etc ? "sleepy/candidates/vm-fixture.json");
  assert builtins.fromJSON candidateConfig.environment.etc."sleepy/candidates/vm-fixture.json".text
  == approvedCandidate
  // {
    schema = 1;
    id = "vm-fixture";
  };
  assert defaultConfig.sleepy.version == "0.1.0";
  assert defaultConfig.users.users.sleepy.isNormalUser;
  assert defaultConfig.services.xserver.xkb.layout == "us";
  assert defaultConfig.services.xserver.xkb.options == "";
  assert !defaultConfig.hardware.bluetooth.enable;
  assert !defaultConfig.sleepy.hardware.nvidia.enable;
  assert !(builtins.elem "nvidia" defaultConfig.services.xserver.videoDrivers);
  assert !defaultConfig.programs.steam.enable;
  assert !defaultConfig.services.flatpak.enable;
  assert !defaultConfig.programs.direnv.enable;
  assert defaultConfig.system.nixos.extraOSReleaseArgs.SLEEPY_VERSION == "0.1.0";
  assert overriddenConfig.sleepy.primaryUser == "sleepy-test";
  assert overriddenConfig.sleepy.version == "9.8.7";
  assert overriddenConfig.users.users.sleepy-test.isNormalUser;
  assert overriddenConfig.system.nixos.extraOSReleaseArgs.SLEEPY_VERSION == "9.8.7";
    pkgs.runCommand "sleepy-public-module-check" {} ''
      # Build the assembled production user-unit directories, not only option
      # values. Different portal derivations can otherwise collide at install.
      test -f ${defaultConfig.environment.etc."systemd/user".source}/xdg-desktop-portal-hyprland.service
      test -f ${profiles.flatpak.environment.etc."systemd/user".source}/xdg-desktop-portal-hyprland.service
      touch "$out"
    ''
