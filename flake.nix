{
  description = "Sleepy Linux desktop foundation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    ...
  }: let
    baseline = import ./hosts/sleepy-vm/baseline.nix;
    supportedSystems = [baseline.system];
    overlay = import ./overlays;
    mkSleepyHost = import ./lib/mkSleepyHost.nix {inherit inputs;};
    forAllSystems = import ./lib/for-all-systems.nix {
      inherit (nixpkgs) lib;
      systems = supportedSystems;
    };
    mkPkgs = system:
      import nixpkgs {
        inherit system;
        overlays = [overlay];
      };
  in {
    packages = forAllSystems (system: let
      pkgs = mkPkgs system;
    in {
      inherit (pkgs) sleepy-branding sleepy-shell;
      default = pkgs.sleepy-shell;
    });

    formatter = forAllSystems (system: (mkPkgs system).alejandra);

    checks = forAllSystems (system:
      import ./checks {
        pkgs = mkPkgs system;
        source = self;
        inherit nixpkgs;
        nixosModule = self.nixosModules.sleepy;
        nixosConfiguration = self.nixosConfigurations.sleepy-vm;
        homeConfiguration = self.homeConfigurations."lazy@sleepy-vm";
      });

    devShells = forAllSystems (system: let
      pkgs = mkPkgs system;
      qmlImportPackages = [
        pkgs.quickshell
        pkgs.qt6Packages.qtdeclarative
      ];
      qmlLint = pkgs.writeShellScriptBin "qmllint" ''
        exec ${pkgs.qt6Packages.qtdeclarative}/bin/qmllint \
          -I ${pkgs.quickshell}/lib/qt-6/qml \
          -I ${pkgs.qt6Packages.qtdeclarative}/lib/qt-6/qml \
          "$@"
      '';
    in {
      default = pkgs.mkShellNoCC {
        packages = with pkgs; [
          alejandra
          deadnix
          git
          qmlLint
          quickshell
          ripgrep
          statix
          shellcheck
          qt6Packages.qtdeclarative
        ];
        QML_IMPORT_PATH = pkgs.lib.makeSearchPath "lib/qt-6/qml" qmlImportPackages;
      };
    });

    overlays.default = overlay;

    nixosModules.sleepy = import ./modules/nixos;
    homeManagerModules.sleepy = import ./modules/home;

    nixosConfigurations.sleepy-vm = import ./hosts/sleepy-vm {
      inherit mkSleepyHost;
    };

    homeConfigurations."lazy@sleepy-vm" = home-manager.lib.homeManagerConfiguration {
      pkgs = mkPkgs baseline.system;
      extraSpecialArgs = {
        inherit inputs;
        primaryUser = "lazy";
        sleepyVersion = "0.1.0";
      };
      modules = [
        self.homeManagerModules.sleepy
        {
          sleepy = {
            enable = true;
            primaryUser = "lazy";
            brandingPackage = self.packages.${baseline.system}.sleepy-branding;
            shellPackage = self.packages.${baseline.system}.sleepy-shell;
          };
          home = {
            username = "lazy";
            homeDirectory = "/home/lazy";
            stateVersion = "26.05";
          };
        }
      ];
    };
  };
}
