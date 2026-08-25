{
  homeConfig,
  pkgs,
  sessionSource,
  shellPackage,
  source,
}: let
  gammastepService = homeConfig.systemd.user.services.gammastep;
  quickshellService = homeConfig.systemd.user.services.quickshell;
  gammastepExec = pkgs.lib.concatStringsSep " " (pkgs.lib.toList gammastepService.Service.ExecStart);
in
  assert pkgs.lib.assertMsg
  (builtins.elem "QML_XHR_ALLOW_FILE_READ=1" (pkgs.lib.toList quickshellService.Service.Environment))
  "the deployed Quickshell service must permit the pinned local artwork manifest";
  assert pkgs.lib.assertMsg
  (gammastepService.Service.Type == "simple")
  "gammastep must remain a continuous service";
  assert pkgs.lib.assertMsg
  (!(pkgs.lib.hasInfix " -O " gammastepExec))
  "gammastep must not use the one-shot temperature command";
  assert pkgs.lib.assertMsg
  (pkgs.lib.hasInfix " -l " gammastepExec && pkgs.lib.hasInfix " -t " gammastepExec)
  "gammastep must have continuous location and temperature policy";
    pkgs.runCommand "sleepy-control-center-contract" {
      nativeBuildInputs = [pkgs.findutils pkgs.gnugrep];
    } ''
      set -eu
      desktop=${shellPackage}/share/sleepy-desktop
      test -d "$desktop"
      shell="$desktop/shell.qml"
      ipc="$desktop/services/ShellIpc.qml"
      ${pkgs.gnugrep}/bin/grep -Fx '//@ pragma ShellId sleepy' "$shell"
      ${pkgs.gnugrep}/bin/grep -Fx '        target: "sleepy"' "$ipc"
      for signature in \
        '        function toggleControlCenter(): void { root.request("toggle", ""); }' \
        '        function openControlCenter(): void { root.request("open", ""); }' \
        '        function closeActiveSurface(): void { root.request("close", ""); }' \
        '        function openPowerMenu(): void { root.request("power", ""); }' \
        '        function requestSessionAction(action: string): void {'; do
        ${pkgs.gnugrep}/bin/grep -Fx -- "$signature" "$ipc"
      done
      ${pkgs.gnugrep}/bin/grep -Fx '      configs.sleepy = "''${config.sleepy.shellPackage}/share/sleepy-desktop";' \
        ${source}/modules/home/quickshell/default.nix
      ${pkgs.gnugrep}/bin/grep -Fx '      activeConfig = "sleepy";' \
        ${source}/modules/home/quickshell/default.nix
      ${pkgs.gnugrep}/bin/grep -Fx '        Requires = ["sleepy-session.service" "sleepy-bindings-online.service"];' \
        ${source}/modules/home/quickshell/default.nix
      ${pkgs.gnugrep}/bin/grep -F 'CommandSpec::new("systemctl", ["--user", "is-active", "gammastep.service"])' \
        ${sessionSource}/src/system/night_light.rs
      touch "$out"
    ''
