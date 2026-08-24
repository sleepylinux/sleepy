{
  componentContract,
  componentPackages,
  inputs,
  integratedHomeConfig,
  pkgs,
  source,
  standaloneHomeConfig,
}: let
  system = pkgs.stdenv.hostPlatform.system;
  reviewedRevision = name: componentContract.inputs.${name}.revision;
  inputRevision = name: inputs.${name}.rev;
  packageContract = name: componentContract.rootPackages.${name};
  expectedPackage = name: let
    contract = packageContract name;
  in
    inputs.${contract.input}.packages.${system}.${contract.output};
  sessionService = standaloneHomeConfig.systemd.user.services.sleepy-session;
  integratedSessionService = integratedHomeConfig.systemd.user.services.sleepy-session;
  expectedSessionExec = ["${componentPackages.sleepy-session}/bin/sleepyctl settings show"];
  actualContract = pkgs.writeText "sleepy-component-contract.json" (builtins.toJSON {
    schemaVersion = 1;
    inherit system;
    revisions = builtins.mapAttrs (name: _: inputRevision name) componentContract.inputs;
    packages =
      builtins.mapAttrs (name: contract: {
        inherit (contract) input output;
        path = toString componentPackages.${name};
      })
      componentContract.rootPackages;
    defaultPackage = toString componentPackages.default;
    homeManager = {
      shellPackage = toString standaloneHomeConfig.sleepy.shellPackage;
      quickshellConfig = standaloneHomeConfig.programs.quickshell.configs.sleepy;
      artworkPackage = toString standaloneHomeConfig.sleepy.brandingPackage;
      sessionPackage = toString standaloneHomeConfig.sleepy.sessionPackage;
      service = {
        unit = "sleepy-session.service";
        wantedBy = sessionService.Install.WantedBy;
        partOf = sessionService.Unit.PartOf;
        after = sessionService.Unit.After;
        requisite = sessionService.Unit.Requisite;
        type = sessionService.Service.Type;
        remainAfterExit = sessionService.Service.RemainAfterExit;
        execStart = sessionService.Service.ExecStart;
      };
    };
    sources = {
      root = toString source;
      sleepy-sdk = toString inputs.sleepy-sdk;
    };
    validators.niri = "${pkgs.niri}/bin/niri";
  });
in
  assert pkgs.lib.assertMsg
  (builtins.all (name: inputRevision name == reviewedRevision name) (builtins.attrNames componentContract.inputs))
  "component inputs must resolve to the reviewed immutable revisions";
  assert pkgs.lib.assertMsg
  (builtins.all (name: componentPackages.${name} == expectedPackage name) (builtins.attrNames componentContract.rootPackages))
  "root package outputs must be direct aliases of the reviewed component outputs";
  assert pkgs.lib.assertMsg
  (builtins.all (name: componentPackages.${name}.meta.license == pkgs.lib.licenses.gpl3Only) (builtins.attrNames componentContract.rootPackages))
  "all externally owned root packages must declare GPL-3.0-only";
  assert pkgs.lib.assertMsg
  (componentPackages.default == componentPackages.${componentContract.defaultPackage})
  "the root default package must remain the external Sleepy shell";
  assert pkgs.lib.assertMsg
  (standaloneHomeConfig.sleepy.shellPackage == componentPackages.sleepy-shell)
  "standalone Home Manager must use the external desktop shell";
  assert pkgs.lib.assertMsg
  (standaloneHomeConfig.programs.quickshell.configs.sleepy == "${componentPackages.sleepy-shell}/share/sleepy-desktop")
  "standalone Quickshell must load the external desktop package layout";
  assert pkgs.lib.assertMsg
  (standaloneHomeConfig.sleepy.brandingPackage == componentPackages.sleepy-artwork)
  "standalone Home Manager must use the external artwork package";
  assert pkgs.lib.assertMsg
  (standaloneHomeConfig.sleepy.sessionPackage == componentPackages.sleepy-session)
  "standalone Home Manager must use the external session package";
  assert pkgs.lib.assertMsg
  (integratedHomeConfig.sleepy.shellPackage == componentPackages.sleepy-shell)
  "integrated Home Manager must use the external desktop shell";
  assert pkgs.lib.assertMsg
  (integratedHomeConfig.programs.quickshell.configs.sleepy == "${componentPackages.sleepy-shell}/share/sleepy-desktop")
  "integrated Quickshell must load the external desktop package layout";
  assert pkgs.lib.assertMsg
  (integratedHomeConfig.sleepy.brandingPackage == componentPackages.sleepy-artwork)
  "integrated Home Manager must use the external artwork package";
  assert pkgs.lib.assertMsg
  (integratedHomeConfig.sleepy.sessionPackage == componentPackages.sleepy-session)
  "integrated Home Manager must use the external session package";
  assert pkgs.lib.assertMsg
  (sessionService == integratedSessionService)
  "standalone and integrated Home Manager must share the session service contract";
  assert pkgs.lib.assertMsg
  (sessionService.Service.ExecStart == expectedSessionExec)
  "the session service must execute sleepyctl from the external session package";
    pkgs.runCommand "sleepy-component-contract" {
      nativeBuildInputs = with pkgs; [
        bash
        coreutils
        findutils
        jq
      ];
    } ''
      bash ${./component-contract.sh} ${../components/desktop-m1.json} ${actualContract}
      touch "$out"
    ''
