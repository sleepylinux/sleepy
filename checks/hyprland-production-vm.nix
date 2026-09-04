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
  selectedSessionName = "Hyprland (uwsm-managed)";
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
  (builtins.elem "graphical-session.target" shellUnit.Unit.After
    && builtins.elem "sleepy-session.service" shellUnit.Unit.Wants
    && builtins.elem "sleepy-session.service" shellUnit.Unit.After
    && !(builtins.elem "sleepy-session.service" (shellUnit.Unit.Requires or [])))
  "the shell must order after the graphical target and daemon readiness without failure coupling";
  assert pkgs.lib.assertMsg
  (builtins.elem "graphical-session.target" lockerUnit.Unit.PartOf
    && builtins.elem "graphical-session.target" shellUnit.Unit.PartOf
    && builtins.elem "graphical-session.target" sessionUnit.Unit.PartOf)
  "candidate services must share the UWSM graphical lifecycle";
    pkgs.testers.runNixOSTest {
      name = "sleepy-hyprland-production";
      enableOCR = true;

      nodes.machine = {
        config,
        lib,
        pkgs,
        ...
      }: let
        regreetTestState = pkgs.writeText "regreet-test-state.toml" ''
          last_user = "lazy"

          [user_to_last_sess]
          lazy = "${selectedSessionName}"
        '';
      in {
        imports = [../modules/nixos];

        sleepy.primaryUser = "lazy";
        system.stateVersion = "26.05";
        users.users.lazy = {
          isNormalUser = true;
          initialHashedPassword = "!";
        };
        # Credential-free test-only PAM: proves the ReGreet/greetd exchange and
        # selected session launch. Real-password PAM remains a manual VM gate.
        security.pam.services.greetd = {
          useDefaultRules = false;
          rules = lib.mkForce {
            auth.permit = {
              order = 100;
              control = "required";
              modulePath = "${config.security.pam.package}/lib/security/pam_permit.so";
            };
            account.permit = {
              order = 100;
              control = "required";
              modulePath = "${config.security.pam.package}/lib/security/pam_permit.so";
            };
            session.env = {
              order = 100;
              control = "required";
              modulePath = "${config.security.pam.package}/lib/security/pam_env.so";
            };
            session.systemd = {
              order = 200;
              control = "required";
              modulePath = "${config.systemd.package}/lib/security/pam_systemd.so";
            };
          };
        };
        services.displayManager.regreet.settings.skip_selection = false;
        # ReGreet officially remembers the last authenticated user/session.
        # Seed that state for this credential-free test so the graphical gate
        # can assert the exact UWSM selection before activating Login, without
        # relying on GTK's layout-dependent tab order.
        systemd.services.greetd.preStart = lib.mkBefore ''
          install -d -o greeter -g greeter -m 0700 /var/lib/regreet
          install -o greeter -g greeter -m 0600 ${regreetTestState} /var/lib/regreet/state.toml
        '';
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
        import re
        import shlex
        from datetime import timedelta

        start_all()
        machine.wait_for_unit("multi-user.target")
        machine.wait_for_unit("greetd.service")

        machine.succeed("test -f /run/current-system/sw/share/wayland-sessions/hyprland-uwsm.desktop")
        session_exec = machine.succeed("sed -n 's/^Exec=//p' /run/current-system/sw/share/wayland-sessions/hyprland-uwsm.desktop").strip()
        session_name = machine.succeed("sed -n 's/^Name=//p' /run/current-system/sw/share/wayland-sessions/hyprland-uwsm.desktop").strip()
        assert session_name == "${selectedSessionName}"
        assert "/bin/uwsm start " in session_exec
        assert session_exec.endswith("hyprland.desktop")
        machine.succeed("! systemctl list-unit-files --no-legend 'niri*.service' | grep -q .")
        machine.succeed("! find /run/current-system/sw -iname '*niri*' -print -quit | grep -q .")

        machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.local /home/lazy/.local/state /home/lazy/.local/share /home/lazy/.local/state/home-manager /home/lazy/.local/state/nix")
        machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.local/state/home-manager/gcroots /home/lazy/.local/state/nix/profiles")
        legacy_env = "HOME=/home/lazy XDG_CONFIG_HOME=/home/lazy/.config XDG_STATE_HOME=/home/lazy/.local/state SLEEPY_NIRI_VALIDATOR=${pkgs.niri}/bin/niri"
        legacy_manifest = "sha256sum /home/lazy/.config/sleepy/settings.json /home/lazy/.local/state/sleepy/presets.json /home/lazy/.config/niri/sleepy-user-bindings.kdl"
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

        # REGREET_LOGIN_GATE: drive the actual graphical greeter and choose
        # the generated UWSM entry instead of Hyprland's direct entry.
        # Nix wrappers intentionally change /proc/$pid/comm (for example to
        # .cage-wrapped), so match the complete argv instead of a mutable
        # wrapper process name.  -x also prevents a partial command match.
        regreet_ready = "pgrep -f -x '${pkgs.cage}/bin/cage -s -d -- ${pkgs.regreet}/bin/regreet' >/dev/null && pgrep -f -x '${pkgs.regreet}/bin/regreet' >/dev/null"
        try:
          machine.wait_until_succeeds(regreet_ready, timeout=timedelta(seconds=30))
        except Exception:
          print(machine.succeed("ps -eo pid,comm,args"))
          print(machine.succeed("systemctl status greetd --no-pager || true"))
          print(machine.succeed("journalctl -b -u greetd --no-pager || true"))
          print(machine.succeed("test ! -f /var/log/greetd/log || cat /var/log/greetd/log"))
          print(machine.succeed("test ! -f /var/log/regreet/log || cat /var/log/regreet/log"))
          raise
        # A live process is not yet an interactive greeter: first require its
        # configuration load, then require GTK-rendered model state via OCR.
        # A cached session intentionally omits the former "Last session ...
        # missing" log, so that absence cannot be used as readiness.
        machine.wait_until_succeeds("grep -F 'Loaded TOML file:' /var/log/regreet/log", timeout=timedelta(seconds=30))
        machine.wait_for_text("Welcome back!", timeout=timedelta(seconds=30))
        machine.wait_for_text(re.escape("${selectedSessionName}"), timeout=timedelta(seconds=30))
        regreet_pid = machine.succeed("pgrep -f -x '${pkgs.regreet}/bin/regreet'").strip()
        # ReGreet focuses Login after initialization.  Return activates the
        # visible, asserted UWSM selection and enters the real greetd exchange.
        machine.send_key("ret")
        try:
          machine.wait_until_succeeds("grep -F 'Creating session for username: lazy' /var/log/regreet/log", timeout=timedelta(seconds=30))
          machine.wait_until_succeeds("grep -F 'Successfully logged in; starting session' /var/log/regreet/log", timeout=timedelta(seconds=30))
        except Exception:
          machine.screenshot("regreet-submit-timeout")
          print(machine.succeed("ps -eo pid,comm,args"))
          print(machine.succeed("journalctl -b -u greetd --no-pager || true"))
          print(machine.succeed("test ! -f /var/log/regreet/log || cat /var/log/regreet/log"))
          raise

        uid = machine.succeed("id -u lazy").strip()
        user_env = f"sudo -u lazy HOME=/home/lazy XDG_RUNTIME_DIR=/run/user/{uid} DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/{uid}/bus"
        hyprland_ready = "pgrep -u lazy -f -x '${hyprlandPackage}/bin/Hyprland --watchdog-fd [0-9]+' >/dev/null"
        niri_absent = "! pgrep -u lazy -f -x '${pkgs.niri}/bin/niri([[:space:]].*)?' >/dev/null"
        machine.wait_until_succeeds(hyprland_ready, timeout=timedelta(seconds=30))
        machine.wait_until_succeeds(f"{user_env} systemctl --user is-active wayland-wm@hyprland.desktop.service", timeout=timedelta(seconds=30))
        machine.wait_until_succeeds(f"{user_env} systemctl --user is-active graphical-session.target", timeout=timedelta(seconds=30))
        machine.succeed("grep -F '/bin/uwsm' /var/log/regreet/log | grep -F 'hyprland.desktop'")

        for unit in ["sleepy-locker.service", "sleepy-session.service", "sleepy-shell.service"]:
          machine.wait_until_succeeds(f"{user_env} systemctl --user is-active {unit}", timeout=timedelta(seconds=30))
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
        while b'\\n' not in data:
            part = s.recv(65536)
            if not part:
                raise SystemExit('desktop socket closed before full snapshot')
            data += part
            if len(data) > 4 * 1024 * 1024:
                raise SystemExit('desktop snapshot exceeded acceptance bound')
        frame, separator, _ = data.partition(b'\\n')
        if not frame or not separator:
            raise SystemExit('desktop socket did not yield a complete first frame')
        open(sys.argv[2], 'wb').write(frame + separator)
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

        shell_stream_probe = r"""import re, subprocess, sys
        socket_path, shell_main_pid, shell_control_group, daemon_main_pid = sys.argv[1:]
        if not shell_main_pid.isdigit() or int(shell_main_pid) < 2:
            raise SystemExit('invalid sleepy-shell supervisor PID')
        if not daemon_main_pid.isdigit() or int(daemon_main_pid) < 2:
            raise SystemExit('invalid sleepy-sessiond PID')
        if not shell_control_group.startswith('/') or not shell_control_group.endswith('/sleepy-shell.service'):
            raise SystemExit('unexpected sleepy-shell control group')

        output = subprocess.check_output(
            ['ss', '-xnpH', 'state', 'established'],
            text=True,
            stderr=subprocess.STDOUT,
        )
        records = []
        for line in output.splitlines():
            fields = line.split(maxsplit=7)
            if len(fields) != 8:
                continue
            records.append((fields[3], fields[4], fields[6], set(re.findall(r'pid=(\d+),', fields[7]))))

        socket_name = socket_path.rsplit('/', 1)[-1]
        server_edges = set()
        for server_address, server_local_id, server_peer_id, server_pids in records:
            if server_address.rsplit('/', 1)[-1] != socket_name:
                continue
            if any(server_pid == daemon_main_pid for server_pid in server_pids):
                server_edges.add((server_local_id, server_peer_id))
        if len(server_edges) != 1:
            raise SystemExit(
                f'expected one {socket_name} edge owned by sleepy-sessiond {daemon_main_pid}, got {sorted(server_edges)}'
            )

        server_local_id, server_peer_id = server_edges.pop()
        candidates = set()
        for _, client_local_id, client_peer_id, client_pids in records:
            if not (client_local_id == server_peer_id and client_peer_id == server_local_id):
                continue
            for peer_pid in client_pids:
                try:
                    with open(f'/proc/{peer_pid}/cgroup', encoding='utf-8') as cgroups:
                        in_shell_cgroup = any(
                            cgroup_line == '0::' + shell_control_group
                            for cgroup_line in map(str.strip, cgroups)
                        )
                except FileNotFoundError:
                    continue
                if not in_shell_cgroup:
                    continue

                ancestor_pid = peer_pid
                while ancestor_pid not in ('0', '1', shell_main_pid):
                    try:
                        with open(f'/proc/{ancestor_pid}/status', encoding='utf-8') as status:
                            match = re.search(r'^PPid:\s+(\d+)$', status.read(), re.MULTILINE)
                    except FileNotFoundError:
                        match = None
                    if match is None:
                        break
                    ancestor_pid = match.group(1)
                if ancestor_pid == shell_main_pid:
                    candidates.add(peer_pid)

        if len(candidates) != 1:
            raise SystemExit(
                f'expected one {socket_name} config process in {shell_control_group}, got {sorted(candidates)}'
            )
        print(candidates.pop())
        """

        def wait_for_shell_stream(shell_main_pid, shell_control_group, daemon_main_pid):
          socket_path = f"/run/user/{uid}/sleepy/desktop.sock"
          peer_file = "/tmp/sleepy-shell-stream-peer.pid"
          probe_command = (
            f"${pkgs.python3}/bin/python3 -c {shlex.quote(shell_stream_probe)} "
            f"{shlex.quote(socket_path)} {shlex.quote(shell_main_pid)} "
            f"{shlex.quote(shell_control_group)} {shlex.quote(daemon_main_pid)} "
            f"> {shlex.quote(peer_file)}"
          )
          try:
            machine.wait_until_succeeds(probe_command, timeout=timedelta(seconds=30))
          except Exception:
            print(machine.succeed("ss -xnpH state established || true"))
            print(machine.succeed(f"{user_env} systemctl --user status sleepy-shell.service --no-pager || true"))
            print(machine.succeed(f"{user_env} journalctl --user -u sleepy-shell.service --no-pager || true"))
            raise
          peer_pid = machine.succeed(f"cat {shlex.quote(peer_file)}").strip()
          assert peer_pid.isdigit()
          return peer_pid

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

        machine.succeed(niri_absent)
        daemon_pid = machine.succeed(f"{user_env} systemctl --user show sleepy-session.service -P MainPID").strip()
        shell_pid = machine.succeed(f"{user_env} systemctl --user show sleepy-shell.service -P MainPID").strip()
        shell_control_group = machine.succeed(f"{user_env} systemctl --user show sleepy-shell.service -P ControlGroup").strip()
        # INITIAL_SHELL_STREAM_GATE: prove the shell completed QML startup and
        # connected before interrupting its daemon.  An active systemd service
        # alone does not establish that recovery is being exercised.
        shell_peer_pid = wait_for_shell_stream(shell_pid, shell_control_group, daemon_pid)
        machine.succeed("sleep 5")
        assert wait_for_shell_stream(shell_pid, shell_control_group, daemon_pid) == shell_peer_pid

        # DAEMON_RESTART_RECOVERY_GATE: reconnect to the replacement
        # daemon socket and validate a fresh full snapshot.
        previous_daemon_pid = daemon_pid
        machine.succeed(f"{user_env} systemctl --user restart sleepy-session.service")
        machine.wait_until_succeeds(f"test $({user_env} systemctl --user show sleepy-session.service -P MainPID) != {shlex.quote(previous_daemon_pid)}", timeout=timedelta(seconds=30))
        daemon_pid = machine.succeed(f"{user_env} systemctl --user show sleepy-session.service -P MainPID").strip()
        machine.wait_until_succeeds(f"{user_env} systemctl --user is-active sleepy-shell.service", timeout=timedelta(seconds=30))
        reconnected_shell_peer_pid = wait_for_shell_stream(shell_pid, shell_control_group, daemon_pid)
        assert reconnected_shell_peer_pid == shell_peer_pid
        post_daemon = read_snapshot("/tmp/desktop-post-daemon.json")
        assert post_daemon["eventId"] != initial_snapshot["eventId"]
        assert wait_for_shell_stream(shell_pid, shell_control_group, daemon_pid) == shell_peer_pid

        # SHELL_RESTART_RECOVERY_GATE: require a replacement shell
        # process and a new authoritative socket read after recovery.
        previous_shell_peer_pid = shell_peer_pid
        machine.succeed(f"{user_env} systemctl --user restart sleepy-shell.service")
        machine.wait_until_succeeds(f"test $({user_env} systemctl --user show sleepy-shell.service -P MainPID) != {shlex.quote(shell_pid)}", timeout=timedelta(seconds=30))
        machine.wait_until_succeeds(f"{user_env} systemctl --user is-active sleepy-shell.service", timeout=timedelta(seconds=30))
        shell_pid = machine.succeed(f"{user_env} systemctl --user show sleepy-shell.service -P MainPID").strip()
        shell_control_group = machine.succeed(f"{user_env} systemctl --user show sleepy-shell.service -P ControlGroup").strip()
        shell_peer_pid = wait_for_shell_stream(shell_pid, shell_control_group, daemon_pid)
        assert shell_peer_pid != previous_shell_peer_pid
        post_shell = read_snapshot("/tmp/desktop-post-shell.json")
        assert post_shell["generation"] >= post_daemon["generation"]

        machine.succeed(f"{user_env} /run/current-system/sw/bin/uwsm stop")
        for unit in ["sleepy-locker.service", "sleepy-session.service", "sleepy-shell.service"]:
          machine.wait_until_fails(f"{user_env} systemctl --user is-active {unit}", timeout=timedelta(seconds=30))
        machine.wait_until_succeeds("systemctl is-active greetd.service", timeout=timedelta(seconds=30))
        machine.wait_until_succeeds(regreet_ready, timeout=timedelta(seconds=30))
        machine.wait_until_succeeds("test $(grep -Fc 'Loaded TOML file' /var/log/regreet/log) -ge 2", timeout=timedelta(seconds=30))
        machine.wait_until_succeeds(f"test $(pgrep -f -x '${pkgs.regreet}/bin/regreet') != {shlex.quote(regreet_pid)}", timeout=timedelta(seconds=30))
        machine.wait_for_text("Welcome back!", timeout=timedelta(seconds=30))

        machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
        assert machine.succeed(legacy_manifest) == prior_hashes
        machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
        assert machine.succeed(legacy_manifest) == prior_hashes
      '';
    }
