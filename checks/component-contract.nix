{
  componentContract,
  componentPackages,
  inputs,
  integratedHomeConfig,
  pkgs,
  standaloneHomeConfig,
}: let
  system = pkgs.stdenv.hostPlatform.system;
  reviewedRevision = name: componentContract.inputs.${name}.revision;
  inputRevision = name: inputs.${name}.rev;
  # The secure locker is also part of the runtime, though the older component
  # manifest predates its separate package output.
  packageContracts =
    componentContract.rootPackages
    // {
      sleepy-locker = {
        input = "sleepy-desktop";
        output = "sleepy-locker";
      };
    };
  packageContract = name: packageContracts.${name};
  expectedPackage = name: let
    contract = packageContract name;
  in
    inputs.${contract.input}.packages.${system}.${contract.output};
  reviewedPatches = {
    sleepy-session = [../patches/session-bounded-audio-refresh.patch];
    sleepy-locker = [../patches/locker-supported-unlock.patch];
    sleepy-shell = [../patches/desktop-bounded-nmcli.patch];
    sleepy-settings-preview = [../patches/desktop-bounded-nmcli.patch];
  };
  matchesReviewedPackage = name: let
    actual = componentPackages.${name};
    upstream = expectedPackage name;
    patches = reviewedPatches.${name} or [];
    patched = upstream.overrideAttrs (old: {
      patches = (old.patches or []) ++ patches;
    });
  in
    if patches == []
    then actual == upstream
    else
      actual
      == patched
      && (actual.sleepyUpstreamPackage or null) == upstream
      && (actual.sleepyDownstreamPatches or []) == patches
      && (actual.patches or []) == (upstream.patches or []) ++ patches
      && actual.src == upstream.src;
  sessionService = standaloneHomeConfig.systemd.user.services.sleepy-session;
  integratedSessionService = integratedHomeConfig.systemd.user.services.sleepy-session;
  shellService = standaloneHomeConfig.systemd.user.services.sleepy-shell;
  integratedShellService = integratedHomeConfig.systemd.user.services.sleepy-shell;
  expectedSessionExec = ["${componentPackages.sleepy-session}/bin/sleepy-sessiond"];
  expectedShellExec = ["${componentPackages.sleepy-shell}/bin/sleepy-shell"];
  actualContract = pkgs.writeText "sleepy-component-contract.json" (builtins.toJSON {
    schemaVersion = 1;
    inherit system;
    revisions = builtins.mapAttrs (name: _: inputRevision name) componentContract.inputs;
    packages =
      builtins.mapAttrs (name: contract: {
        inherit (contract) input output;
        path = toString componentPackages.${name};
        downstreamPatches = map (patch: {
          name = builtins.baseNameOf patch;
          sha256 = builtins.hashFile "sha256" patch;
        }) (reviewedPatches.${name} or []);
      })
      packageContracts;
    defaultPackage = toString componentPackages.default;
    homeManager = {
      shellPackage = toString standaloneHomeConfig.sleepy.shellPackage;
      shellUnit = "sleepy-shell.service";
      shellExecStart = pkgs.lib.toList shellService.Service.ExecStart;
      artworkPackage = toString standaloneHomeConfig.sleepy.brandingPackage;
      sessionPackage = toString standaloneHomeConfig.sleepy.sessionPackage;
      service = {
        unit = "sleepy-session.service";
        wantedBy = sessionService.Install.WantedBy;
        partOf = sessionService.Unit.PartOf;
        wants = sessionService.Unit.Wants;
        after = sessionService.Unit.After;
        requisite = sessionService.Unit.Requisite;
        requires = sessionService.Unit.Requires;
        type = sessionService.Service.Type;
        notifyAccess = sessionService.Service.NotifyAccess;
        restart = sessionService.Service.Restart;
        runtimeDirectory = sessionService.Service.RuntimeDirectory;
        runtimeDirectoryMode = sessionService.Service.RuntimeDirectoryMode;
        killSignal = sessionService.Service.KillSignal;
        timeoutStopSec = sessionService.Service.TimeoutStopSec;
        environment = sessionService.Service.Environment;
        execStart = sessionService.Service.ExecStart;
      };
    };
    sources."sleepy-sdk" = toString inputs.sleepy-sdk;
  });
in
  assert pkgs.lib.assertMsg
  (builtins.all (name: inputRevision name == reviewedRevision name) (builtins.attrNames componentContract.inputs))
  "component inputs must resolve to the reviewed immutable revisions";
  assert pkgs.lib.assertMsg
  (builtins.all matchesReviewedPackage (builtins.attrNames packageContracts))
  "root packages must use reviewed component outputs and explicitly reviewed downstream patches";
  assert pkgs.lib.assertMsg
  (builtins.all (name: componentPackages.${name}.meta.license == pkgs.lib.licenses.gpl3Only) (builtins.attrNames packageContracts))
  "all externally owned root packages must declare GPL-3.0-only";
  assert pkgs.lib.assertMsg
  (componentPackages.default == componentPackages.${componentContract.defaultPackage})
  "the root default package must remain the external Sleepy shell";
  assert pkgs.lib.assertMsg
  (standaloneHomeConfig.sleepy.lockerPackage
    == componentPackages.sleepy-locker
    && integratedHomeConfig.sleepy.lockerPackage == componentPackages.sleepy-locker)
  "both Home Manager configurations must use the reviewed secure locker";
  assert pkgs.lib.assertMsg
  (standaloneHomeConfig.sleepy.shellPackage == componentPackages.sleepy-shell)
  "standalone Home Manager must use the external desktop shell";
  assert pkgs.lib.assertMsg
  (pkgs.lib.toList shellService.Service.ExecStart == expectedShellExec)
  "standalone shell service must execute the external desktop wrapper";
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
  (pkgs.lib.toList integratedShellService.Service.ExecStart == expectedShellExec)
  "integrated shell service must execute the external desktop wrapper";
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
  (shellService == integratedShellService)
  "standalone and integrated Home Manager must share the shell service contract";
  assert pkgs.lib.assertMsg
  (!(standaloneHomeConfig.systemd.user.services ? quickshell)
    && !(integratedHomeConfig.systemd.user.services ? quickshell))
  "the generic quickshell.service name must not remain in the candidate graph";
  assert pkgs.lib.assertMsg
  (sessionService.Service.ExecStart == expectedSessionExec)
  "the session service must execute sleepy-sessiond from the external session package";
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
