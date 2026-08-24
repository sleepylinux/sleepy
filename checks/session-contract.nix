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
  (builtins.elem pkgs.quickshell config.environment.systemPackages)
  "Quickshell must belong to the candidate system closure for deployment attestation";
  assert pkgs.lib.assertMsg
  (builtins.elem pkgs.grim config.environment.systemPackages)
  "grim must belong to the candidate system closure for deployment screenshots";
  assert pkgs.lib.assertMsg
  (builtins.elem pkgs.jq config.environment.systemPackages)
  "jq must belong to the candidate system closure for deployment validation";
  assert pkgs.lib.assertMsg
  (builtins.elem pkgs.git config.environment.systemPackages)
  "git must belong to the candidate system closure for archive provenance";
  assert pkgs.lib.assertMsg
  (!(config.systemd.user.services ? xwayland-satellite))
  "Niri owns Xwayland Satellite; Sleepy must not define a user service";
  assert pkgs.lib.assertMsg
  (!(config.systemd.services ? xwayland-satellite))
  "Niri owns Xwayland Satellite; Sleepy must not define a system service";
  assert pkgs.lib.assertMsg
  (builtins.elem niriPackage config.systemd.packages)
  "the upstream Niri systemd package must be installed";
  assert pkgs.lib.assertMsg
  (pkgs.lib.versionAtLeast niriPackage.version "26.04")
  "the configured Niri package must satisfy the M2 minimum";
    pkgs.runCommand "session-contract" {} ''
      test -x ${niriPackage}/bin/niri-session
      test -f ${niriPackage}/lib/systemd/user/niri.service
      test -f ${niriPackage}/share/wayland-sessions/niri.desktop
      test -L ${config.system.build.toplevel}/sw
      test -x ${config.system.build.toplevel}/sw/bin/quickshell
      test -x ${config.system.build.toplevel}/sw/bin/grim
      test -x ${config.system.build.toplevel}/sw/bin/jq
      test -x ${config.system.build.toplevel}/sw/bin/git
      test "$(readlink -f ${config.system.build.toplevel}/sw/bin/quickshell)" = \
        ${pkgs.quickshell}/bin/quickshell
      test "$(readlink -f ${config.system.build.toplevel}/sw/bin/grim)" = \
        ${pkgs.grim}/bin/grim
      test "$(readlink -f ${config.system.build.toplevel}/sw/bin/jq)" = \
        ${pkgs.jq}/bin/jq
      test "$(readlink -f ${config.system.build.toplevel}/sw/bin/git)" = \
        ${pkgs.git}/bin/git
      touch "$out"
    ''
