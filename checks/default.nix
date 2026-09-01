{
  componentContract,
  componentPackages,
  baselineActivationPackage,
  baselineSessionPackage,
  homeConfiguration,
  inputs,
  nixosModule,
  nixosConfiguration,
  nixpkgs,
  pkgs,
  source,
}: let
  integratedHomeConfig =
    nixosConfiguration.config.home-manager.users.${homeConfiguration.config.home.username};
  componentIntegration = import ./component-contract.nix {
    inherit
      componentContract
      componentPackages
      inputs
      integratedHomeConfig
      pkgs
      ;
    standaloneHomeConfig = homeConfiguration.config;
  };
  appsContract = import ./apps-contract.nix {
    inherit pkgs integratedHomeConfig;
    standaloneHomeConfig = homeConfiguration.config;
    nixosConfig = nixosConfiguration.config;
  };
  hyprlandConfig = pkgs.callPackage ./hyprland-config.nix {
    homeConfig = integratedHomeConfig;
  };
  controlCenterContract = pkgs.callPackage ./control-center-contract.nix {
    inherit source;
    homeConfig = homeConfiguration.config;
    sessionSource = inputs.sleepy-session;
    shellPackage = componentPackages.sleepy-shell;
  };
  publicModule = import ./public-module.nix {
    inherit nixosModule nixpkgs pkgs;
  };
  sessionContract = import ./session-contract.nix {
    inherit pkgs;
    homeConfig = integratedHomeConfig;
    inherit (nixosConfiguration) config;
  };
  lockerLifecycle = import ./locker-lifecycle.nix {
    inherit pkgs;
    homeConfig = integratedHomeConfig;
    nixosConfig = nixosConfiguration.config;
  };
  updateSafety = pkgs.callPackage ./update-safety.nix {
    inherit (homeConfiguration) activationPackage;
    inherit baselineActivationPackage;
  };
  updateSafetyVm = pkgs.callPackage ./update-safety-vm.nix {
    inherit baselineActivationPackage baselineSessionPackage;
    inherit (homeConfiguration) activationPackage;
    sessionPackage = componentPackages.sleepy-session;
  };
  fallbackBranding = pkgs.callPackage ../packages/sleepy-branding {};
  fallbackShell = pkgs.callPackage ../packages/sleepy-shell {
    sleepy-branding = fallbackBranding;
  };
  sourceContracts =
    pkgs.runCommand "sleepy-source-contracts" {
      nativeBuildInputs = with pkgs; [
        bash
        coreutils
        findutils
        gawk
        git
        gnused
        jq
        ripgrep
      ];
    } ''
      ${pkgs.bash}/bin/bash ${source}/checks/source-clean.sh ${source}
      ${pkgs.bash}/bin/bash ${source}/checks/source-clean-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/baseline-provenance-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/component-contract-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/component-lock-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/current-component-pins-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/flake-shape-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/flake-input-contract-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/license-contract-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/journal-fault-runner-source-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/update-safety-contract-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/root-integration-contract-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/desktop-m3-root-contract-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/locker-lifecycle-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/hyprland-session-contract-test.sh
      ${pkgs.bash}/bin/bash ${source}/checks/hyprland-user-config-test.sh
      touch "$out"
    '';
  freshCloneSource = pkgs.runCommand "sleepy-fresh-clone-source-check" {} ''
    test -e ${sourceContracts}
    test -e ${nixosConfiguration.config.system.build.toplevel}
    test -f ${source}/flake.nix
    test -f ${source}/flake.lock
    test ! -e ${source}/local
    test ! -e ${source}/secrets
    ${pkgs.coreutils}/bin/sha256sum ${source}/flake.lock >"$out"
  '';
  quickshell =
    pkgs.runCommand "sleepy-quickshell-check" {
      LC_ALL = "C.UTF-8";
      nativeBuildInputs = with pkgs; [
        bash
        findutils
        qt6Packages.qtdeclarative
        ripgrep
      ];
    } ''
      ${pkgs.bash}/bin/bash ${source}/checks/quickshell-contract-test.sh

      while IFS= read -r -d "" qml_file; do
        ${pkgs.qt6Packages.qtdeclarative}/bin/qmllint \
          -I ${pkgs.quickshell}/lib/qt-6/qml \
          -I ${pkgs.qt6Packages.qtdeclarative}/lib/qt-6/qml \
          "$qml_file"
      done < <(${pkgs.findutils}/bin/find ${source}/packages/sleepy-shell/src -name '*.qml' -print0)

      test -f ${fallbackShell}/share/quickshell/sleepy/shell.qml
      touch "$out"
    '';
in
  assert pkgs.lib.assertMsg
  (fallbackBranding.meta.license == pkgs.lib.licenses.gpl3Only)
  "the retained branding fallback must declare GPL-3.0-only";
  assert pkgs.lib.assertMsg
  (fallbackShell.meta.license == pkgs.lib.licenses.gpl3Only)
  "the retained shell fallback must declare GPL-3.0-only"; {
    apps-contract = appsContract;
    component-contract = componentIntegration;
    control-center-contract = controlCenterContract;
    nixos = nixosConfiguration.config.system.build.toplevel;
    home = homeConfiguration.activationPackage;
    hyprland-config = hyprlandConfig;
    public-module = publicModule;
    session-contract = sessionContract;
    update-safety = updateSafety;
    update-safety-vm = updateSafetyVm;
    pristine-login-vm = updateSafetyVm;
    source-contracts = sourceContracts;
    journal-fault-runner = pkgs.callPackage ./journal-fault-runner.nix {
      runner = componentPackages.sleepy-journal-fault-runner;
    };
    locker-lifecycle = lockerLifecycle;
    fresh-clone-source = freshCloneSource;
    inherit quickshell;
    sleepy-artwork-assets = inputs.sleepy-artwork.checks.${pkgs.stdenv.hostPlatform.system}.assets;
    sleepy-desktop-qml = inputs.sleepy-desktop.checks.${pkgs.stdenv.hostPlatform.system}.qml;
    sleepy-desktop-package = inputs.sleepy-desktop.checks.${pkgs.stdenv.hostPlatform.system}.package;
    sleepy-desktop-preview = inputs.sleepy-desktop.checks.${pkgs.stdenv.hostPlatform.system}.preview;
  }
