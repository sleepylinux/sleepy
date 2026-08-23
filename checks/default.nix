{
  homeConfiguration,
  nixosModule,
  nixosConfiguration,
  nixpkgs,
  pkgs,
  source,
}: let
  integratedHomeConfig =
    nixosConfiguration.config.home-manager.users.${homeConfiguration.config.home.username};
  appsContract = import ./apps-contract.nix {
    inherit pkgs integratedHomeConfig;
    standaloneHomeConfig = homeConfiguration.config;
    nixosConfig = nixosConfiguration.config;
  };
  niriConfig = pkgs.callPackage ./niri-config.nix {};
  publicModule = import ./public-module.nix {
    inherit nixosModule nixpkgs pkgs;
  };
  sessionContract = import ./session-contract.nix {
    inherit pkgs;
    inherit (nixosConfiguration) config;
  };
  updateSafety = pkgs.callPackage ./update-safety.nix {
    inherit (homeConfiguration) activationPackage;
  };
  sourceContracts =
    pkgs.runCommand "sleepy-source-contracts" {
      nativeBuildInputs = with pkgs; [
        bash
        findutils
        git
        ripgrep
      ];
    } ''
      ${pkgs.bash}/bin/bash ${source}/checks/source-clean.sh ${source}
      ${pkgs.bash}/bin/bash ${source}/checks/source-clean-test.sh
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

      test -f ${pkgs.sleepy-shell}/share/quickshell/sleepy/shell.qml
      touch "$out"
    '';
in {
  apps-contract = appsContract;
  nixos = nixosConfiguration.config.system.build.toplevel;
  home = homeConfiguration.activationPackage;
  niri-config = niriConfig;
  public-module = publicModule;
  session-contract = sessionContract;
  update-safety = updateSafety;
  source-contracts = sourceContracts;
  fresh-clone-source = freshCloneSource;
  inherit quickshell;
}
