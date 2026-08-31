{
  homeConfig,
  nixosConfig,
  pkgs,
}: let
  locker = homeConfig.systemd.user.services.sleepy-locker;
  failsafe = homeConfig.systemd.user.services.sleepy-locker-failsafe;
  session = homeConfig.systemd.user.services.sleepy-session;
  pamFile = nixosConfig.environment.etc."pam.d/sleepy-locker".source;
in
  assert pkgs.lib.assertMsg
  (nixosConfig.security.pam.services ? sleepy-locker)
  "Sleepy must define a root-owned sleepy-locker PAM service";
  assert pkgs.lib.assertMsg
  (builtins.elem "graphical-session.target" locker.Unit.PartOf)
  "the locker must stop with the UWSM graphical session";
  assert pkgs.lib.assertMsg
  (builtins.elem "graphical-session.target" locker.Unit.After)
  "the locker must start after the UWSM graphical session environment";
  assert pkgs.lib.assertMsg
  (builtins.elem "sleepy-locker-failsafe.service" locker.Unit.OnFailure)
  "locker exhaustion must activate the fixed fail-safe unit";
  assert pkgs.lib.assertMsg
  (locker.Service.ExecStart == "${homeConfig.sleepy.lockerPackage}/bin/sleepy-locker")
  "the locker unit must execute the pinned package binary";
  assert pkgs.lib.assertMsg
  (locker.Service.Restart == "always")
  "the persistent locker must restart after every unexpected exit";
  assert pkgs.lib.assertMsg
  (failsafe.Service.ExecStart == "${pkgs.uwsm}/bin/uwsm stop")
  "the locker fail-safe must terminate the UWSM session with a fixed command";
  assert pkgs.lib.assertMsg
  (builtins.elem "sleepy-locker.service" session.Unit.Wants)
  "the session daemon must start the independently supervised locker";
  assert pkgs.lib.assertMsg
  (!(builtins.elem "sleepy-locker.service" (session.Unit.Requires or [])))
  "the daemon must not own the locker lifecycle";
  assert pkgs.lib.assertMsg
  (builtins.elem "SLEEPY_LOCKER_SOCKET=%t/sleepy/locker.sock" session.Service.Environment)
  "the daemon and locker must share only the private locker endpoint";
    pkgs.runCommand "sleepy-locker-lifecycle" {} ''
      test -f ${pamFile}
      test -x ${homeConfig.sleepy.lockerPackage}/bin/sleepy-locker
      touch "$out"
    ''
