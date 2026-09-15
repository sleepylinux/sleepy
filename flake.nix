{
  description = "Sleepy Linux desktop foundation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-sdk = {
      url = "github:sleepylinux/sleepy-sdk/c7d7452163d4fdfa000634e2196212a53d8b159f";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-session = {
      url = "github:sleepylinux/sleepy-session/341d69fcb245f41b56e72e8ac89630a5e1b7d4e2";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        sleepy-sdk.follows = "sleepy-sdk";
      };
    };

    sleepy-artwork = {
      url = "github:sleepylinux/sleepy-artwork/ac3feed1e81b4e74a84a326c1f53f3ddaf94aa3e";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    sleepy-desktop = {
      url = "github:sleepylinux/sleepy-desktop/5710631354df0f54d97a46d8ceae7f0bcae69b80";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        sleepy-artwork.follows = "sleepy-artwork";
        sleepy-sdk.follows = "sleepy-sdk";
        sleepy-session.follows = "sleepy-session";
      };
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
      sleepy-update = pkgs.callPackage ./packages/sleepy-update {
        nix = import ./packages/vendor/nix-with-git {inherit pkgs;};
      };
      sleepy-installer = pkgs.callPackage ./packages/sleepy-installer {
        source = self;
        nix = import ./packages/vendor/nix-with-git {inherit pkgs;};
      };
      installer-iso = self.nixosConfigurations.sleepy-installer.config.system.build.isoImage;
      inherit
        (pkgs)
        sleepy-artwork
        sleepy-branding
        sleepy-contract
        sleepy-journal-fault-runner
        sleepy-locker
        sleepy-qt-wayland-focus
        sleepy-session
        sleepy-session-user-unit
        sleepy-settings-preview
        sleepy-shell
        ;
      default = pkgs.sleepy-shell;
    });

    formatter = forAllSystems (system: (mkPkgs system).alejandra);

    checks = forAllSystems (system: let
      baselineChecks = import ./lib/baseline-check-packages.nix {inherit inputs system;};
    in
      (import ./checks {
        pkgs = mkPkgs system;
        source = self;
        inherit componentContract inputs nixpkgs;
        componentPackages = self.packages.${system};
        nixosModule = self.nixosModules.sleepy;
        nixosConfiguration = self.nixosConfigurations.sleepy-vm;
        homeConfiguration = self.homeConfigurations."lazy@sleepy-vm";
        baselineActivationPackage = baselineChecks.activationPackage;
        baselineSessionPackage = baselineChecks.sessionPackage;
      })
      // {
        installer = (mkPkgs system).callPackage ./checks/installer.nix {};
        flatpak-recovery = import ./checks/flatpak-recovery.nix {pkgs = mkPkgs system;};
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
          pngcheck
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

    lib = {inherit mkSleepyHost;};

    nixosModules.sleepy = import ./modules/nixos;
    homeManagerModules.sleepy = import ./modules/home;

    nixosConfigurations.sleepy-vm = import ./hosts/sleepy-vm {
      inherit mkSleepyHost;
    };

    nixosConfigurations.sleepy-installer = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hosts/sleepy-installer
        {environment.systemPackages = [self.packages.x86_64-linux.sleepy-installer];}
      ];
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
            lockerPackage = self.packages.${baseline.system}.sleepy-locker;
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
