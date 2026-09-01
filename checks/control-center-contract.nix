{
  homeConfig,
  pkgs,
  sessionSource,
  shellPackage,
  source,
}: let
  gammastepService = homeConfig.systemd.user.services.gammastep;
  quickshellService = homeConfig.systemd.user.services.sleepy-shell;
  gammastepExec = pkgs.lib.concatStringsSep " " (pkgs.lib.toList gammastepService.Service.ExecStart);
in
  assert pkgs.lib.assertMsg
  (builtins.elem "QML_XHR_ALLOW_FILE_READ=1" (pkgs.lib.toList quickshellService.Service.Environment))
  "the deployed Quickshell service must permit the pinned local artwork manifest";
  assert pkgs.lib.assertMsg
  (pkgs.lib.toList quickshellService.Service.ExecStart == ["${shellPackage}/bin/sleepy-shell"])
  "the deployed Quickshell service must use the version-matched desktop wrapper";
  assert pkgs.lib.assertMsg
  (gammastepService.Service.Type == "simple")
  "gammastep must remain a continuous service";
  assert pkgs.lib.assertMsg
  (!(pkgs.lib.hasInfix " -O " gammastepExec))
  "gammastep must not use the one-shot temperature command";
  assert pkgs.lib.assertMsg
  (builtins.elem "sleepy-session.service" quickshellService.Unit.Wants
    && builtins.elem "sleepy-session.service" quickshellService.Unit.After
    && !(builtins.elem "sleepy-session.service" (quickshellService.Unit.Requires or [])))
  "Quickshell must order after daemon readiness without sharing failure fate";
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
      ipc="$desktop/core/CoreDesktopWindows.qml"
      ${pkgs.gnugrep}/bin/grep -Fx '//@ pragma ShellId sleepy' "$shell"
      ${pkgs.gnugrep}/bin/grep -Fx '        target: "sleepy"' "$ipc"
      for signature in \
        '        function toggleLauncher(): void { ipcRouter.toggle("launcher"); }' \
        '        function toggleNotifications(): void { ipcRouter.toggle("notifications"); }' \
        '        function toggleDashboard(): void { ipcRouter.toggle("dashboard"); }' \
        '        function toggleNexus(): void { ipcRouter.toggle("nexus"); }' \
        '        function closeOverlay(): void { ipcRouter.close(); }' \
        '        function mediaPlayPause(): void { ipcRouter.media("playPause"); }' \
        '        function mediaNext(): void { ipcRouter.media("next"); }' \
        '        function mediaPrevious(): void { ipcRouter.media("previous"); }' \
        '        function lock(): void { ipcRouter.lock(); }' \
        '        function openPowerMenu(): void { ipcRouter.openPowerMenu(); }'; do
        ${pkgs.gnugrep}/bin/grep -Fx -- "$signature" "$ipc"
      done
      ${pkgs.gnugrep}/bin/grep -Fx '        ExecStart = "''${config.sleepy.shellPackage}/bin/sleepy-shell";' \
        ${source}/modules/home/quickshell/default.nix
      ${pkgs.gnugrep}/bin/grep -Fx '        Wants = ["sleepy-session.service"];' \
        ${source}/modules/home/quickshell/default.nix
      ${pkgs.gnugrep}/bin/grep -F 'CommandSpec::new("systemctl", ["--user", "is-active", "gammastep.service"])' \
        ${sessionSource}/src/system/night_light.rs
      touch "$out"
    ''
