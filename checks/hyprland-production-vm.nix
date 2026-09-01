{
  activationPackage,
  baselineActivationPackage,
  baselineSessionPackage,
  homeConfig,
  lockerPackage,
  nixosConfig,
  pkgs,
  sdkSource,
  sessionPackage,
  shellPackage,
}: let
  sessionUnit = homeConfig.systemd.user.services.sleepy-session;
  shellUnit = homeConfig.systemd.user.services.sleepy-shell;
  lockerUnit = homeConfig.systemd.user.services.sleepy-locker;
  hyprlandPackage = nixosConfig.programs.hyprland.package;
  eventSchema = "${sdkSource}/schemas/desktop-event-v3.schema.json";
  schemaPython = pkgs.python3.withPackages (pythonPackages: [pythonPackages.jsonschema]);
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

      nodes.machine = {
        lib,
        pkgs,
        ...
      }: {
        imports = [../modules/nixos];

        sleepy.primaryUser = "lazy";
        system.stateVersion = "26.05";
        users.users.lazy = {
          isNormalUser = true;
          initialHashedPassword = "!";
        };
        # Credential-free test-only PAM: proves the ReGreet/greetd exchange and
        # selected session launch. Real-password PAM remains a manual VM gate.
        security.pam.services.greetd.text = lib.mkForce ''
          auth required pam_permit.so
          account required pam_permit.so
          session required pam_env.so
          session required pam_systemd.so
        '';
        services.displayManager.regreet.settings.skip_selection = false;
        services.qemuGuest.enable = true;
        environment.systemPackages = [
          pkgs.coreutils
          pkgs.findutils
          pkgs.iproute2
          pkgs.jq
          pkgs.procps
          pkgs.python3
          pkgs.socat
          pkgs.util-linux
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
            pkgs.niri
            schemaPython
            sessionPackage
            shellPackage
            lockerPackage
          ];
        };
      };

      testScript = ''
                import json
                import shlex

                start_all()
                machine.wait_for_unit("multi-user.target")
                machine.wait_for_unit("greetd.service")

                machine.succeed("test -f /run/current-system/sw/share/wayland-sessions/hyprland-uwsm.desktop")
                session_exec = machine.succeed("sed -n 's/^Exec=//p' /run/current-system/sw/share/wayland-sessions/hyprland-uwsm.desktop").strip()
                assert "/bin/uwsm start " in session_exec
                assert session_exec.endswith("hyprland.desktop")
                machine.succeed("! systemctl list-unit-files --no-legend 'niri*.service' | grep -q .")
                machine.succeed("! find /run/current-system/sw -iname '*niri*' -print -quit | grep -q .")

                machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.local /home/lazy/.local/state /home/lazy/.local/share /home/lazy/.local/state/home-manager /home/lazy/.local/state/nix")
                machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.local/state/home-manager/gcroots /home/lazy/.local/state/nix/profiles")
                legacy_env = "HOME=/home/lazy XDG_CONFIG_HOME=/home/lazy/.config XDG_STATE_HOME=/home/lazy/.local/state SLEEPY_NIRI_VALIDATOR=${pkgs.niri}/bin/niri"
                legacy_manifest = "(find /home/lazy/.config/sleepy /home/lazy/.local/state/sleepy -xdev -type f -print0 2>/dev/null; find /home/lazy/.config/niri -maxdepth 1 -type f -name 'sleepy-user-bindings.kdl' -print0 2>/dev/null) | sort -z | xargs -0 -r sha256sum"
                machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
                machine.succeed(f"sudo -u lazy {legacy_env} ${baselineSessionPackage}/bin/sleepyctl presets duplicate builtin.sleepy 'Production VM preserved preset' >/dev/null")
                machine.succeed(f"sudo -u lazy {legacy_env} ${baselineSessionPackage}/bin/sleepyctl bindings reconcile >/dev/null")
                machine.succeed("test -f /home/lazy/.config/sleepy/settings.json && test -f /home/lazy/.local/state/sleepy/presets.json && test -f /home/lazy/.config/niri/sleepy-user-bindings.kdl")
                prior_hashes = machine.succeed(legacy_manifest)

                machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
                assert machine.succeed(legacy_manifest) == prior_hashes
                machine.succeed("test -L /home/lazy/.config/hypr/hyprland.conf")
                machine.succeed("test -f /home/lazy/.config/hypr/sleepy-user.conf")
                machine.succeed("test $(stat -c %a /home/lazy/.config/hypr/sleepy-user.conf) = 600")
                machine.succeed("test ! -e /home/lazy/.config/niri/config.kdl")

                # REGREET_LOGIN_GATE: drive the actual graphical greeter. Its
                # only available Wayland desktop is the generated UWSM entry.
                machine.wait_until_succeeds("pgrep -x cage >/dev/null && pgrep -x regreet >/dev/null")
                machine.send_chars("lazy")
                machine.send_key("tab")
                machine.send_key("tab")
                machine.send_key("ret")
                machine.wait_until_succeeds("grep -F 'Creating session for username: lazy' /var/log/regreet/log")
                machine.wait_until_succeeds("grep -F 'Successfully logged in; starting session' /var/log/regreet/log")

                uid = machine.succeed("id -u lazy").strip()
                user_env = f"sudo -u lazy HOME=/home/lazy XDG_RUNTIME_DIR=/run/user/{uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
                machine.wait_until_succeeds("pgrep -u lazy -x Hyprland >/dev/null")
                machine.wait_until_succeeds(f"{user_env} systemctl --user is-active wayland-wm@Hyprland.desktop.target")
                machine.wait_until_succeeds(f"{user_env} systemctl --user is-active graphical-session.target")
                machine.succeed("grep -F '/bin/uwsm' /var/log/regreet/log | grep -F 'hyprland.desktop'")

                for unit in ["sleepy-locker.service", "sleepy-session.service", "sleepy-shell.service"]:
                  machine.wait_until_succeeds(f"{user_env} systemctl --user is-active {unit}")
                machine.succeed(f"{user_env} systemctl --user show sleepy-session.service -P Type | grep -Fx notify")
                machine.succeed(f"{user_env} systemctl --user show sleepy-shell.service -P After | tr ' ' '\\n' | grep -Fx sleepy-session.service")
                machine.succeed(f"! {user_env} systemctl --user show sleepy-shell.service -P Requires | tr ' ' '\\n' | grep -Fx sleepy-session.service")
                machine.succeed(f"test -S /run/user/{uid}/sleepy/desktop.sock")
                machine.succeed(f"test $(stat -c %a /run/user/{uid}/sleepy/desktop.sock) = 600")

                reader = """import socket, sys
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(15)
        s.connect(sys.argv[1])
        data = bytes()
        while not data.endswith(b'\\n'):
            part = s.recv(65536)
            if not part:
                raise SystemExit('desktop socket closed before full snapshot')
            data += part
            if len(data) > 4 * 1024 * 1024:
                raise SystemExit('desktop snapshot exceeded acceptance bound')
        open(sys.argv[2], 'wb').write(data)
        """
                validator = """import json, sys
        from jsonschema import Draft202012Validator, FormatChecker
        schema = json.load(open(sys.argv[1], encoding='utf-8'))
        document = json.load(open(sys.argv[2], encoding='utf-8'))
        Draft202012Validator(schema, format_checker=FormatChecker()).validate(document)
        if document['payload']['type'] != 'fullSnapshot':
            raise SystemExit('first desktop frame is not a fullSnapshot')
        if type(document['generation']) is not int or document['generation'] < 1:
            raise SystemExit('desktop generation is not a positive integer')
        """

                def read_snapshot(path):
                  socket_path = f"/run/user/{uid}/sleepy/desktop.sock"
                  machine.succeed(f"{user_env} ${pkgs.python3}/bin/python3 -c {shlex.quote(reader)} {shlex.quote(socket_path)} {shlex.quote(path)}")
                  machine.succeed(f"${schemaPython}/bin/python3 -c {shlex.quote(validator)} ${eventSchema} {shlex.quote(path)}")
                  return json.loads(machine.succeed(f"cat {shlex.quote(path)}"))

                def wait_for_shell_stream(shell_main_pid):
                  socket_path = f"/run/user/{uid}/sleepy/desktop.sock"
                  machine.wait_until_succeeds(
                    f"ss -xnp | grep -F {shlex.quote(socket_path)} | grep -F {shlex.quote('pid=' + shell_main_pid + ',')}"
                  )

                initial_snapshot = read_snapshot("/tmp/desktop-initial.json")

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
                daemon_pid = machine.succeed(f"{user_env} systemctl --user show sleepy-session.service -P MainPID").strip()
                shell_pid = machine.succeed(f"{user_env} systemctl --user show sleepy-shell.service -P MainPID").strip()

                # DAEMON_RESTART_RECOVERY_GATE: reconnect to the replacement
                # daemon socket and validate a fresh full snapshot.
                machine.succeed(f"{user_env} systemctl --user restart sleepy-session.service")
                machine.wait_until_succeeds(f"test $({user_env} systemctl --user show sleepy-session.service -P MainPID) != {shlex.quote(daemon_pid)}")
                machine.wait_until_succeeds(f"{user_env} systemctl --user is-active sleepy-shell.service")
                wait_for_shell_stream(shell_pid)
                post_daemon = read_snapshot("/tmp/desktop-post-daemon.json")
                assert post_daemon["eventId"] != initial_snapshot["eventId"]

                # SHELL_RESTART_RECOVERY_GATE: require a replacement shell
                # process and a new authoritative socket read after recovery.
                machine.succeed(f"{user_env} systemctl --user restart sleepy-shell.service")
                machine.wait_until_succeeds(f"test $({user_env} systemctl --user show sleepy-shell.service -P MainPID) != {shlex.quote(shell_pid)}")
                machine.wait_until_succeeds(f"{user_env} systemctl --user is-active sleepy-shell.service")
                shell_pid = machine.succeed(f"{user_env} systemctl --user show sleepy-shell.service -P MainPID").strip()
                wait_for_shell_stream(shell_pid)
                post_shell = read_snapshot("/tmp/desktop-post-shell.json")
                assert post_shell["generation"] >= post_daemon["generation"]

                machine.succeed(f"{user_env} /run/current-system/sw/bin/uwsm stop")
                for unit in ["sleepy-locker.service", "sleepy-session.service", "sleepy-shell.service"]:
                  machine.wait_until_fails(f"{user_env} systemctl --user is-active {unit}")
                machine.wait_until_succeeds("systemctl is-active greetd.service")
                machine.wait_until_succeeds("pgrep -x regreet >/dev/null")

                machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
                assert machine.succeed(legacy_manifest) == prior_hashes
                machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
                assert machine.succeed(legacy_manifest) == prior_hashes
      '';
    }
