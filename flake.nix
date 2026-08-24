{
  description = "Sleepy Linux desktop foundation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-sdk = {
      url = "github:sleepylinux/sleepy-sdk/4c4f7989b957f41f3748ddfb092b0348e2ba9e88";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-session = {
      url = "github:sleepylinux/sleepy-session/76937a484ffa444572c9ae1460029e573fb108ca";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-artwork = {
      url = "github:sleepylinux/sleepy-artwork/7785ac5dac0daa6ac1a619f1e2a9a1b1d1374da1";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-desktop = {
      url = "github:sleepylinux/sleepy-desktop/b69fd4d97895600e029e10621a61113ad795dbd8";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs @ {
    self,
    nixpkgs,
    home-manager,
    ...
  }: let
    componentContract = builtins.fromJSON (builtins.readFile ./components/desktop-m1.json);
    baseline = import ./hosts/sleepy-vm/baseline.nix;
    supportedSystems = [baseline.system];
    overlay = import ./overlays {inherit inputs;};
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
      inherit (pkgs)
        sleepy-artwork
        sleepy-branding
        sleepy-contract
        sleepy-session
        sleepy-session-user-unit
        sleepy-settings-preview
        sleepy-shell;
      default = pkgs.sleepy-shell;
    });

    formatter = forAllSystems (system: (mkPkgs system).alejandra);

    checks = forAllSystems (system:
      import ./checks {
        pkgs = mkPkgs system;
        source = self;
        inherit componentContract inputs nixpkgs;
        componentPackages = self.packages.${system};
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
            brandingPackage = self.packages.${baseline.system}.sleepy-artwork;
            sessionPackage = self.packages.${baseline.system}.sleepy-session;
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
