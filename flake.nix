{
  description = "Sleepy Linux desktop foundation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-sdk = {
      url = "github:sleepylinux/sleepy-sdk/152173b470fa7d1e90c6d3d6be103a4a4d3529bc";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-session = {
      url = "github:sleepylinux/sleepy-session/03eef8fa32595d7887ed36830212f9abc6c01a84";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-artwork = {
      url = "github:sleepylinux/sleepy-artwork/175314b9c236c1b412e8e1ebc54bbe3937b0c90d";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-desktop = {
      url = "github:sleepylinux/sleepy-desktop/e52bf09a6472366d182209de9ea083a69364721c";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-m2-baseline = {
      url = "github:sleepylinux/sleepy/563ae07b50ccc8c5332e1fb0352d351d46c7f615";
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
      inherit
        (pkgs)
        sleepy-artwork
        sleepy-branding
        sleepy-contract
        sleepy-journal-fault-runner
        sleepy-session
        sleepy-session-user-unit
        sleepy-settings-preview
        sleepy-shell
        ;
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
        baselineActivationPackage = inputs.sleepy-m2-baseline.homeConfigurations."lazy@sleepy-vm".activationPackage;
        baselineSessionPackage = inputs.sleepy-m2-baseline.packages.${system}.sleepy-session;
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
          jq
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
