{
  config,
  homeConfig,
  pkgs,
}: let
  hyprlandPackage = config.programs.hyprland.package;
  uwsmPackage = config.programs.uwsm.package;
  portalPreference = config.xdg.portal.config.common;
  session = homeConfig.systemd.user.services.sleepy-session;
  shell = homeConfig.systemd.user.services.sleepy-shell;
  locker = homeConfig.systemd.user.services.sleepy-locker;
  clipboard = homeConfig.systemd.user.services.sleepy-clipboard;
  polkitAgent = config.systemd.user.services.polkit-gnome-authentication-agent-1;
  keyring = config.systemd.user.services.gnome-keyring-daemon;
in
  assert pkgs.lib.assertMsg config.programs.hyprland.enable
  "Sleepy must enable the upstream Hyprland module";
  assert pkgs.lib.assertMsg config.programs.hyprland.xwayland.enable
  "Sleepy must enable XWayland through the Hyprland module";
  assert pkgs.lib.assertMsg config.programs.hyprland.withUWSM
  "ReGreet must launch the UWSM-managed Hyprland session";
  assert pkgs.lib.assertMsg config.programs.uwsm.enable
  "Sleepy must enable UWSM";
  assert pkgs.lib.assertMsg (!config.programs.niri.enable)
  "Niri must not remain enabled in the candidate generation";
  assert pkgs.lib.assertMsg config.services.greetd.enable
  "Sleepy must keep greetd enabled";
  assert pkgs.lib.assertMsg config.services.displayManager.regreet.enable
  "Sleepy must keep ReGreet enabled";
  assert pkgs.lib.assertMsg (!(config.services.displayManager.autoLogin.enable or false))
  "Sleepy must not enable display-manager autologin";
  assert pkgs.lib.assertMsg config.xdg.portal.enable
  "Sleepy must enable desktop portals";
  assert pkgs.lib.assertMsg
  (portalPreference.default == "hyprland;gtk")
  "portal fallback order must be hyprland;gtk";
  assert pkgs.lib.assertMsg
  (portalPreference."org.freedesktop.impl.portal.FileChooser" == "gtk")
  "GTK must own the FileChooser portal";
  assert pkgs.lib.assertMsg
  (portalPreference."org.freedesktop.impl.portal.ScreenCast"
    == "hyprland"
    && portalPreference."org.freedesktop.impl.portal.Screenshot" == "hyprland")
  "Hyprland must own screencast and screenshot portals";
  assert pkgs.lib.assertMsg
  (builtins.elem pkgs.xdg-desktop-portal-hyprland config.xdg.portal.extraPortals
    && builtins.elem pkgs.xdg-desktop-portal-gtk config.xdg.portal.extraPortals)
  "the Hyprland and GTK portal backends must be in the candidate closure";
  assert pkgs.lib.assertMsg
  (!(builtins.elem pkgs.niri config.environment.systemPackages)
    && !(builtins.elem pkgs.xwayland-satellite config.environment.systemPackages))
  "the candidate session PATH must not contain Niri or Xwayland Satellite";
  assert pkgs.lib.assertMsg
  (homeConfig.wayland.windowManager.hyprland.enable
    && !homeConfig.wayland.windowManager.hyprland.systemd.enable
    && homeConfig.wayland.windowManager.hyprland.configType == "hyprlang")
  "Home Manager must author Hyprland config without owning UWSM's target";
  assert pkgs.lib.assertMsg (homeConfig.xdg.configFile ? "uwsm/env")
  "Home Manager variables must be imported through UWSM";
  assert pkgs.lib.assertMsg (session.Service.Type == "notify")
  "sleepy-sessiond readiness must use sd_notify";
  assert pkgs.lib.assertMsg
  (builtins.elem "graphical-session.target" session.Unit.PartOf
    && builtins.elem "graphical-session.target" session.Install.WantedBy)
  "sleepy-sessiond must share UWSM's graphical lifecycle";
  assert pkgs.lib.assertMsg
  (builtins.elem "sleepy-session.service" shell.Unit.Wants
    && builtins.elem "sleepy-session.service" shell.Unit.After
    && !(builtins.elem "sleepy-session.service" (shell.Unit.Requires or [])))
  "the shell must order after daemon readiness without failure coupling";
  assert pkgs.lib.assertMsg
  (pkgs.lib.toList shell.Service.ExecStart == ["${homeConfig.sleepy.shellPackage}/bin/sleepy-shell"])
  "the shell service must execute the version-matched desktop wrapper";
  assert pkgs.lib.assertMsg
  (!(homeConfig.systemd.user.services ? quickshell))
  "the generic quickshell.service name must not remain in the candidate graph";
  assert pkgs.lib.assertMsg
  (builtins.elem "graphical-session.target" locker.Unit.PartOf
    && builtins.elem "graphical-session.target" clipboard.Unit.PartOf)
  "locker and clipboard helper must stop with the UWSM graphical session";
  assert pkgs.lib.assertMsg
  (builtins.elem "graphical-session.target" polkitAgent.partOf
    && builtins.elem "graphical-session.target" keyring.partOf
    && builtins.elem "graphical-session.target" keyring.after)
  "policy agent and keyring must share the active UWSM graphical lifecycle";
  assert pkgs.lib.assertMsg config.services.openssh.enable
  "Sleepy VM must retain OpenSSH maintenance access";
  assert pkgs.lib.assertMsg config.services.openssh.openFirewall
  "Sleepy VM must permit SSH through the firewall";
  assert pkgs.lib.assertMsg
  (builtins.elem pkgs.grim config.environment.systemPackages
    && builtins.elem pkgs.jq config.environment.systemPackages
    && builtins.elem pkgs.git config.environment.systemPackages
    && builtins.elem pkgs.ripgrep config.environment.systemPackages)
  "deployment attestation tools must remain in the candidate closure";
  assert pkgs.lib.assertMsg
  (pkgs.lib.hasInfix "org.freedesktop.UPower.PowerProfiles.switch-profile" config.security.polkit.extraConfig
    && pkgs.lib.hasInfix "subject.isInGroup(\"wheel\")" config.security.polkit.extraConfig)
  "power profile authorization must remain scoped to wheel users";
    pkgs.runCommand "session-contract" {
      nativeBuildInputs = [pkgs.gnugrep];
    } ''
      set -eu

      test -x ${hyprlandPackage}/bin/Hyprland
      test -x ${uwsmPackage}/bin/uwsm
      session_file=${config.system.build.toplevel}/sw/share/wayland-sessions/hyprland-uwsm.desktop
      test -f "$session_file"
      grep -Fx 'Exec=${uwsmPackage}/bin/uwsm start -e -D Hyprland hyprland.desktop' "$session_file"
      grep -Fx 'TryExec=${uwsmPackage}/bin/uwsm' "$session_file"

      test -L ${config.system.build.toplevel}/sw
      for binary in grim jq git rg; do
        test -x ${config.system.build.toplevel}/sw/bin/$binary
      done
      touch "$out"
    ''
