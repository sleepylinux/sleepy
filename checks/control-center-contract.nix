{
  homeConfig,
  pkgs,
  sessionSource,
  shellPackage,
  source,
}: let
  gammastepService = homeConfig.systemd.user.services.gammastep;
in
  assert pkgs.lib.assertMsg
  (gammastepService.Service.Type == "simple")
  "gammastep must remain a continuous service";
  assert pkgs.lib.assertMsg
  (!(pkgs.lib.hasInfix " -O " gammastepService.Service.ExecStart))
  "gammastep must not use the one-shot temperature command";
  assert pkgs.lib.assertMsg
  (pkgs.lib.hasInfix " -l " gammastepService.Service.ExecStart && pkgs.lib.hasInfix " -t " gammastepService.Service.ExecStart)
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
  ${pkgs.gnugrep}/bin/grep -Fx '        Requires = ["sleepy-bindings-online.service"];' \
    ${source}/modules/home/quickshell/default.nix
  ${pkgs.gnugrep}/bin/grep -F 'CommandSpec::new("systemctl", ["--user", "is-active", "gammastep.service"])' \
    ${sessionSource}/src/system/night_light.rs
  touch "$out"
''
