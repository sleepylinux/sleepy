{
  config,
  pkgs,
}: let
  niriPackage = config.programs.niri.package;
in
  assert pkgs.lib.assertMsg config.programs.niri.enable "Sleepy must enable the upstream Niri module";
  assert pkgs.lib.assertMsg config.services.greetd.enable "Sleepy must enable greetd";
  assert pkgs.lib.assertMsg config.services.openssh.enable "Sleepy VM must retain OpenSSH maintenance access";
  assert pkgs.lib.assertMsg config.services.openssh.openFirewall "Sleepy VM must permit SSH through the firewall";
  assert pkgs.lib.assertMsg
  (builtins.elem pkgs.xwayland-satellite config.environment.systemPackages)
  "xwayland-satellite must be available in the Niri session PATH";
  assert pkgs.lib.assertMsg
  (!(config.systemd.user.services ? xwayland-satellite))
  "Niri owns Xwayland Satellite; Sleepy must not define a user service";
  assert pkgs.lib.assertMsg
  (!(config.systemd.services ? xwayland-satellite))
  "Niri owns Xwayland Satellite; Sleepy must not define a system service";
  assert pkgs.lib.assertMsg
  (builtins.elem niriPackage config.systemd.packages)
  "the upstream Niri systemd package must be installed";
    pkgs.runCommand "session-contract" {} ''
      test -x ${niriPackage}/bin/niri-session
      test -f ${niriPackage}/lib/systemd/user/niri.service
      test -f ${niriPackage}/share/wayland-sessions/niri.desktop
      touch "$out"
    ''
