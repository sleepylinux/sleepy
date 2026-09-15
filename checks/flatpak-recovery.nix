{pkgs}: let
  inherit (pkgs) lib;
  probe = pkgs.writeShellScript "flatpak-registration-probe" ''
    echo attempt >> /var/lib/registration-attempts
    case "$(cat /var/lib/registration-mode)" in
      offline) exit 1 ;;
      stalled) exec ${pkgs.coreutils}/bin/sleep 300 ;;
      online) touch /var/lib/registered ;;
      *) exit 2 ;;
    esac
  '';
in
  pkgs.testers.runNixOSTest {
    name = "sleepy-flatpak-recovery";
    nodes.machine = {...}: {
      imports = [../modules/nixos/hardware];
      sleepy.features.flatpak.enable = true;
      xdg.portal.enable = true;
      xdg.portal.extraPortals = [pkgs.xdg-desktop-portal-gtk];
      # Exercise the production unit and real systemd scheduling; replace only
      # the remote server operation, avoiding public-network dependence in CI.
      systemd = {
        services.sleepy-flathub.serviceConfig.ExecStart = lib.mkForce probe;
        tmpfiles.rules = ["f /var/lib/registration-mode 0600 root root - offline"];
        timers.sleepy-flathub.timerConfig = {
          OnBootSec = lib.mkForce "2s";
          OnUnitInactiveSec = lib.mkForce "2s";
          AccuracySec = lib.mkForce "100ms";
        };
      };
      virtualisation.memorySize = 768;
    };
    testScript = ''
      start_all()
      machine.wait_for_unit("multi-user.target")
      machine.wait_until_succeeds("test -f /var/lib/registration-attempts")
      machine.fail("test -f /var/lib/registered")
      machine.succeed("echo online > /var/lib/registration-mode")
      machine.wait_until_succeeds("test -f /var/lib/registered", timeout=30)
      machine.wait_until_succeeds("systemctl is-active sleepy-flathub.service", timeout=10)
      attempts = machine.succeed("wc -l < /var/lib/registration-attempts").strip()
      # An elapsed timer must not rerun successful registration.
      machine.sleep(5)
      assert machine.succeed("wc -l < /var/lib/registration-attempts").strip() == attempts
      # A stuck remote operation must also terminate under the production bound.
      machine.succeed("systemctl stop sleepy-flathub.timer sleepy-flathub.service; echo stalled > /var/lib/registration-mode")
      machine.succeed("systemctl start --no-block sleepy-flathub.service")
      machine.wait_until_succeeds("test $(systemctl show -p ActiveState --value sleepy-flathub.service) = activating", timeout=10)
      machine.succeed("systemctl is-active multi-user.target")
      machine.wait_until_succeeds("test $(systemctl show -p Result --value sleepy-flathub.service) = timeout", timeout=60)
      machine.wait_until_succeeds("test $(systemctl show -p MainPID --value sleepy-flathub.service) = 0", timeout=10)
      machine.succeed("echo online > /var/lib/registration-mode; systemctl start sleepy-flathub.timer")
      machine.wait_until_succeeds("systemctl is-active sleepy-flathub.service", timeout=30)
    '';
  }
