{
  activationPackage,
  baselineActivationPackage,
  baselineSessionPackage,
  homeConfig,
  lockerPackage,
  nixosConfig,
  pkgs,
  sessionPackage,
  shellPackage,
}: let
  sessionUnit = homeConfig.systemd.user.services.sleepy-session;
  shellUnit = homeConfig.systemd.user.services.sleepy-shell;
  lockerUnit = homeConfig.systemd.user.services.sleepy-locker;
  hyprlandPackage = nixosConfig.programs.hyprland.package;
in
  assert pkgs.lib.assertMsg nixosConfig.services.greetd.enable
  "production acceptance requires greetd";
  assert pkgs.lib.assertMsg nixosConfig.services.displayManager.regreet.enable
  "production acceptance requires ReGreet";
  assert pkgs.lib.assertMsg nixosConfig.programs.hyprland.withUWSM
  "production acceptance requires the UWSM Hyprland session entry";
  assert pkgs.lib.assertMsg (!nixosConfig.programs.niri.enable)
  "production acceptance must not enable Niri";
  assert pkgs.lib.assertMsg
  (sessionUnit.Service.Type
    == "notify"
    && sessionUnit.Service.NotifyAccess == "main")
  "sleepy-sessiond must signal readiness before shell startup";
  assert pkgs.lib.assertMsg
  (builtins.elem "sleepy-session.service" shellUnit.Unit.Wants
    && builtins.elem "sleepy-session.service" shellUnit.Unit.After
    && !(builtins.elem "sleepy-session.service" (shellUnit.Unit.Requires or [])))
  "the shell must order after daemon readiness without failure coupling";
  assert pkgs.lib.assertMsg
  (builtins.elem "graphical-session.target" lockerUnit.Unit.PartOf
    && builtins.elem "graphical-session.target" shellUnit.Unit.PartOf
    && builtins.elem "graphical-session.target" sessionUnit.Unit.PartOf)
  "candidate services must share the UWSM graphical lifecycle";
    pkgs.testers.runNixOSTest {
      name = "sleepy-hyprland-production";

      nodes.machine = {pkgs, ...}: {
        imports = [../modules/nixos];

        sleepy.primaryUser = "lazy";
        system.stateVersion = "26.05";
        users.users.lazy = {
          isNormalUser = true;
          initialHashedPassword = "!";
        };
        services.qemuGuest.enable = true;
        environment.systemPackages = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.jq
          pkgs.procps
          pkgs.python3
          pkgs.socat
          pkgs.util-linux
          pkgs.weston
          hyprlandPackage
          sessionPackage
          shellPackage
          lockerPackage
        ];
        virtualisation = {
          cores = 2;
          memorySize = 4096;
          graphics = true;
          additionalPaths = [
            activationPackage
            baselineActivationPackage
            baselineSessionPackage
            sessionPackage
            shellPackage
            lockerPackage
          ];
        };
      };

      testScript = ''
                import shlex

                start_all()
                machine.wait_for_unit("multi-user.target")
                machine.wait_for_unit("greetd.service")

                machine.succeed("test -f /run/current-system/sw/share/wayland-sessions/hyprland-uwsm.desktop")
                machine.succeed("grep -F '${nixosConfig.programs.uwsm.package}/bin/uwsm start -e -D Hyprland hyprland.desktop' /run/current-system/sw/share/wayland-sessions/hyprland-uwsm.desktop")
                machine.succeed("! systemctl list-unit-files --no-legend 'niri*.service' | grep -q .")
                machine.succeed("! find /run/current-system/sw -iname '*niri*' -print -quit | grep -q .")

                machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.local /home/lazy/.local/state /home/lazy/.local/share /home/lazy/.local/state/home-manager /home/lazy/.local/state/nix")
                machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.local/state/home-manager/gcroots /home/lazy/.local/state/nix/profiles")
                machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
                machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.local/state/sleepy")
                machine.succeed("printf '%s\\n' prior-generation-preserved | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/production-vm-sentinel")
                prior_hash = machine.succeed("sha256sum /home/lazy/.local/state/sleepy/production-vm-sentinel")

                machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
                assert machine.succeed("sha256sum /home/lazy/.local/state/sleepy/production-vm-sentinel") == prior_hash
                machine.succeed("test -L /home/lazy/.config/hypr/hyprland.conf")
                machine.succeed("test -f /home/lazy/.config/hypr/sleepy-user.conf")
                machine.succeed("test $(stat -c %a /home/lazy/.config/hypr/sleepy-user.conf) = 600")
                machine.succeed("test ! -e /home/lazy/.config/niri/config.kdl")

                machine.succeed("loginctl enable-linger lazy")
                machine.succeed("uid=$(id -u lazy); systemctl start user@$uid.service")
                uid = machine.succeed("id -u lazy").strip()
                user_env = f"sudo -u lazy HOME=/home/lazy XDG_RUNTIME_DIR=/run/user/{uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
                machine.succeed(f"{user_env} systemctl --user daemon-reload")
                machine.succeed(f"{user_env} systemctl --user set-environment XDG_SESSION_TYPE=wayland XDG_CURRENT_DESKTOP=Hyprland QT_QUICK_BACKEND=software QSG_RHI_BACKEND=software LIBGL_ALWAYS_SOFTWARE=1")

                machine.succeed(
                  f"{user_env} systemd-run --user --unit=sleepy-test-weston.service "
                  "--property=Type=simple --setenv=LIBGL_ALWAYS_SOFTWARE=1 "
                  "${pkgs.weston}/bin/weston --backend=headless-backend.so --socket=wayland-parent --idle-time=0"
                )
                machine.wait_until_succeeds(f"test -S /run/user/{uid}/wayland-parent")
                machine.succeed(
                  f"{user_env} systemd-run --user --unit=sleepy-test-hyprland.service "
                  "--property=Type=simple --setenv=WAYLAND_DISPLAY=wayland-parent "
                  "--setenv=XDG_SESSION_TYPE=wayland --setenv=XDG_CURRENT_DESKTOP=Hyprland "
                  "--setenv=LIBGL_ALWAYS_SOFTWARE=1 "
                  "${hyprlandPackage}/bin/Hyprland --config /home/lazy/.config/hypr/hyprland.conf"
                )
                machine.wait_until_succeeds(f"{user_env} systemctl --user is-active sleepy-test-hyprland.service")
                machine.wait_until_succeeds(f"test $(find /run/user/{uid}/hypr -mindepth 1 -maxdepth 1 -type d | wc -l) = 1")
                signature = machine.succeed(f"basename $(find /run/user/{uid}/hypr -mindepth 1 -maxdepth 1 -type d)").strip()
                wayland_display = machine.succeed(f"basename $(find /run/user/{uid} -maxdepth 1 -type s -name 'wayland-*' ! -name wayland-parent | head -n1)").strip()
                assert signature
                assert wayland_display
                machine.succeed(f"{user_env} systemctl --user set-environment HYPRLAND_INSTANCE_SIGNATURE={shlex.quote(signature)} WAYLAND_DISPLAY={shlex.quote(wayland_display)}")
                machine.succeed(f"{user_env} systemctl --user start graphical-session.target")

                for unit in ["sleepy-locker.service", "sleepy-session.service", "sleepy-shell.service"]:
                  machine.wait_until_succeeds(f"{user_env} systemctl --user is-active {unit}")
                machine.succeed(f"{user_env} systemctl --user show sleepy-session.service -P Type | grep -Fx notify")
                machine.succeed(f"{user_env} systemctl --user show sleepy-shell.service -P After | tr ' ' '\\n' | grep -Fx sleepy-session.service")
                machine.succeed(f"! {user_env} systemctl --user show sleepy-shell.service -P Requires | tr ' ' '\\n' | grep -Fx sleepy-session.service")
                machine.succeed(f"test -S /run/user/{uid}/sleepy/desktop.sock")
                machine.succeed(f"test $(stat -c %a /run/user/{uid}/sleepy/desktop.sock) = 600")

                reader = """import socket
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(%r)
        data = bytes()
        while not data.endswith(b'\\n'):
            part = s.recv(65536)
            if not part:
                raise SystemExit('desktop socket closed before full snapshot')
            data += part
            if len(data) > 4 * 1024 * 1024:
                raise SystemExit('desktop snapshot exceeded acceptance bound')
        open('/tmp/desktop-v3.json', 'wb').write(data)
        """ % f"/run/user/{uid}/sleepy/desktop.sock"
                machine.succeed(f"{user_env} ${pkgs.python3}/bin/python3 -c {shlex.quote(reader)}")
                machine.succeed("jq -e '.schemaVersion == 3 and .payload.type == \"fullSnapshot\" and (.generation | type == \"number\") and (.payload.data.system | type == \"object\") and (.payload.data.compositor.hyprland.status == \"available\") and (.payload.data.notifications | type == \"object\") and (.payload.data.launcher | type == \"object\") and (.payload.data.appearance | type == \"object\") and (.payload.data.utilities | type == \"object\")' /tmp/desktop-v3.json >/dev/null")

                for surface in [
                  "shell.qml",
                  "core/CoreDesktopWindows.qml",
                  "core/CoreDashboardView.qml",
                  "core/CoreOsd.qml",
                  "modules/background/SleepyBackground.qml",
                  "modules/session/SleepySession.qml",
                  "modules/utilities/SleepyUtilities.qml",
                  "modules/windowinfo/SleepyWindowInfo.qml",
                ]:
                  machine.succeed(f"test -f ${shellPackage}/share/sleepy-desktop/{surface}")

                machine.succeed("! pgrep -x niri")
                machine.succeed(f"{user_env} systemctl --user restart sleepy-session.service")
                machine.wait_until_succeeds(f"{user_env} systemctl --user is-active sleepy-session.service")
                machine.wait_until_succeeds(f"{user_env} systemctl --user is-active sleepy-shell.service")
                machine.succeed(f"{user_env} systemctl --user restart sleepy-shell.service")
                machine.wait_until_succeeds(f"{user_env} systemctl --user is-active sleepy-shell.service")

                machine.succeed(f"{user_env} systemctl --user stop graphical-session.target")
                for unit in ["sleepy-locker.service", "sleepy-session.service", "sleepy-shell.service"]:
                  machine.wait_until_fails(f"{user_env} systemctl --user is-active {unit}")
                machine.succeed(f"{user_env} systemctl --user stop sleepy-test-hyprland.service sleepy-test-weston.service")
                machine.wait_until_succeeds("systemctl is-active greetd.service")

                machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
                assert machine.succeed("sha256sum /home/lazy/.local/state/sleepy/production-vm-sentinel") == prior_hash
                machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
                assert machine.succeed("sha256sum /home/lazy/.local/state/sleepy/production-vm-sentinel") == prior_hash
      '';
    }
