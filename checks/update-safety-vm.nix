{
  activationPackage,
  baselineActivationPackage,
  baselineSessionPackage,
  pkgs,
  sessionPackage,
}:
pkgs.testers.runNixOSTest {
  name = "sleepy-m2-to-m3-update-safety";

  nodes.machine = {pkgs, ...}: {
    users.users.lazy = {
      isNormalUser = true;
      home = "/home/lazy";
    };
    environment.systemPackages = [pkgs.niri sessionPackage];
    virtualisation.additionalPaths = [baselineActivationPackage baselineSessionPackage activationPackage];
  };

  testScript = ''
    import difflib

    start_all()
    machine.wait_for_unit("multi-user.target")

    env = "HOME=/home/lazy XDG_CONFIG_HOME=/home/lazy/.config XDG_STATE_HOME=/home/lazy/.local/state SLEEPY_NIRI_VALIDATOR=${pkgs.niri}/bin/niri"
    state_manifest = "(find /home/lazy/.config/sleepy -xdev -type f -print0 2>/dev/null; find /home/lazy/.local/state/sleepy -xdev -type f ! -name 'bindings-transaction.json' ! -name '.bindings-transaction.json.*' -print0 2>/dev/null; find /home/lazy/.config/niri -maxdepth 1 -type f \\( -name 'sleepy-user-bindings.kdl' -o -name '.sleepy-user-bindings.kdl.*' \\) -print0 2>/dev/null) | sort -z | xargs -0 -r sha256sum"
    preserved_state_manifest = "printf '%s\\0' /home/lazy/.config/sleepy/settings.json /home/lazy/.config/sleepy/themes/11111111-1111-4111-8111-111111111111.json /home/lazy/.config/sleepy/overrides.json /home/lazy/.local/state/sleepy/presets.json /home/lazy/.local/state/sleepy/themes/current.json /home/lazy/.local/state/sleepy/launcher.json /home/lazy/.local/state/sleepy/notifications/active.json /home/lazy/.local/state/sleepy/notifications/archive.json /home/lazy/.local/state/sleepy/notifications/preferences.json /home/lazy/.config/niri/sleepy-user-bindings.kdl | sort -z | xargs -0 sha256sum"
    hm_bootstrap = "install -d -o lazy -g users -m 700 /home/lazy/.local /home/lazy/.local/state /home/lazy/.local/share /home/lazy/.local/state/home-manager /home/lazy/.local/state/nix && install -d -o lazy -g users -m 700 /home/lazy/.local/state/home-manager/gcroots /home/lazy/.local/state/nix/profiles"

    def assert_state_unchanged(label, before, manifest=state_manifest):
        after = machine.succeed(manifest)
        assert after == before, label + " changed user state:\n" + "".join(
            difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True))
        )

    def start_and_check_session():
        machine.succeed("loginctl enable-linger lazy")
        machine.succeed("uid=$(id -u lazy); systemctl start user@$uid.service")
        machine.succeed("uid=$(id -u lazy); install -d -o lazy -g users -m 700 /run/user/$uid/systemd/user && printf '%s\\n' '[Unit]' 'Wants=graphical-session.target' 'After=graphical-session-pre.target' | install -o lazy -g users -m 600 /dev/stdin /run/user/$uid/systemd/user/sleepy-test-session.target")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user daemon-reload")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user start sleepy-test-session.target")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user is-active graphical-session.target")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user start sleepy-session.service")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user is-active sleepy-session.service")
        machine.wait_until_succeeds("uid=$(id -u lazy); test -S /run/user/$uid/sleepy/session.sock && test $(stat -c %a /run/user/$uid/sleepy/session.sock) = 600")
        machine.succeed("uid=$(id -u lazy); test -S /run/user/$uid/sleepy/control.sock && test $(stat -c %a /run/user/$uid/sleepy/control.sock) = 600")
        machine.succeed("uid=$(id -u lazy); test -S /run/user/$uid/sleepy/notification.sock && test $(stat -c %a /run/user/$uid/sleepy/notification.sock) = 600")
        machine.succeed("uid=$(id -u lazy); test -S /run/user/$uid/sleepy/osd.sock && test $(stat -c %a /run/user/$uid/sleepy/osd.sock) = 600")
        machine.succeed("uid=$(id -u lazy); test -S /run/user/$uid/sleepy/daily.sock && test $(stat -c %a /run/user/$uid/sleepy/daily.sock) = 600")
        machine.succeed("uid=$(id -u lazy); test -S /run/user/$uid/sleepy/theme.sock && test $(stat -c %a /run/user/$uid/sleepy/theme.sock) = 600")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user stop sleepy-session.service")
        machine.wait_until_succeeds("uid=$(id -u lazy); test ! -e /run/user/$uid/sleepy")

    def stop_user_session_manager():
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user stop sleepy-test-session.target graphical-session.target")
        machine.succeed("uid=$(id -u lazy); systemctl stop user@$uid.service")
        machine.succeed("loginctl disable-linger lazy")
        machine.wait_until_succeeds("uid=$(id -u lazy); test ! -e /run/user/$uid")

    # Historical activation is the first writer in this isolated VM home.
    machine.succeed("test ! -e /home/lazy/.config/sleepy/settings.json")
    machine.succeed("test ! -e /home/lazy/.local/state/sleepy/presets.json")
    machine.succeed(hm_bootstrap)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    machine.succeed("test -f /home/lazy/.config/sleepy/settings.json")
    machine.succeed("test -f /home/lazy/.local/state/sleepy/presets.json")
    machine.succeed("test -f /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    for static_name in ["config", "input", "appearance", "bindings-core", "rules", "startup"]:
        machine.succeed(f"test -L /home/lazy/.config/niri/{static_name}.kdl")

    # Seed only user-owned files. Historical Home Manager links remain intact
    # until the candidate generation legitimately replaces them.
    machine.succeed(f"sudo -u lazy {env} ${baselineSessionPackage}/bin/sleepyctl presets duplicate builtin.sleepy 'VM preserved preset' >/dev/null")
    machine.succeed(f"sudo -u lazy {env} ${baselineSessionPackage}/bin/sleepyctl bindings reconcile >/dev/null")
    # Seed every M3 durable domain before the candidate activation. None is
    # Home Manager-owned, and startup must preserve every valid document.
    machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.config/sleepy/themes /home/lazy/.local/state/sleepy/themes /home/lazy/.local/state/sleepy/notifications")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"id\":\"11111111-1111-4111-8111-111111111111\",\"name\":\"VM preserved theme\",\"origin\":\"user\",\"appearance\":\"dark\",\"effects\":\"reduced\",\"reducedMotion\":true,\"opaqueFallback\":false,\"colors\":{\"background\":\"#101010\",\"surface\":\"#181818\",\"textPrimary\":\"#FFFFFF\",\"textSecondary\":\"#E0E0E0\",\"accent\":\"#80BFFF\",\"control\":\"#FFFFFF\"}}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.config/sleepy/themes/11111111-1111-4111-8111-111111111111.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"id\":\"builtin.sleepy-dark\",\"name\":\"Sleepy Dark\",\"origin\":\"builtin\",\"appearance\":\"dark\",\"effects\":\"full\",\"reducedMotion\":false,\"opaqueFallback\":false,\"colors\":{\"background\":\"#10131A\",\"surface\":\"#181D27\",\"textPrimary\":\"#F7F9FC\",\"textSecondary\":\"#D8DEE9\",\"accent\":\"#8EC5FF\",\"control\":\"#F7F9FC\"}}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/themes/current.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"overrides\":{\"weatherEndpoint\":\"https://example.invalid/weather\"}}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.config/sleepy/overrides.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"entries\":{\"org.example.App.desktop\":{\"count\":3,\"lastUsed\":42}}}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/launcher.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"notifications\":[{\"schemaVersion\":2,\"id\":11,\"applicationId\":\"org.example.Active\",\"summary\":\"Message 11\",\"body\":\"Preserve active\",\"urgency\":\"normal\",\"createdAt\":\"2026-08-24T21:00:00Z\",\"timeoutMs\":5000,\"read\":false,\"archived\":false,\"actions\":[{\"id\":\"open\",\"label\":\"Open\",\"state\":\"expired\"}]}]}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/notifications/active.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"notifications\":[{\"schemaVersion\":2,\"id\":12,\"applicationId\":\"org.example.Archive\",\"summary\":\"Archived 12\",\"body\":\"Preserve archive\",\"urgency\":\"low\",\"createdAt\":\"2026-08-24T20:00:00Z\",\"read\":true,\"archived\":true,\"actions\":[]}]}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/notifications/archive.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"dnd\":true,\"nextNotificationId\":20}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/notifications/preferences.json")

    before = machine.succeed(state_manifest)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    assert_state_unchanged("repeat M2 activation", before)
    for static_name in ["config", "input", "appearance", "bindings-core", "rules", "startup"]:
        machine.succeed(f"test -L /home/lazy/.config/niri/{static_name}.kdl")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert_state_unchanged("M2 to M3 activation", before)
    for static_name in ["config", "input", "appearance", "bindings-core", "rules", "startup"]:
        machine.succeed(f"test -L /home/lazy/.config/niri/{static_name}.kdl")
    machine.succeed("test ! -e /home/lazy/.config/niri/bindings.kdl")
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl bindings reconcile >/dev/null")
    assert_state_unchanged("M3 bindings reconciliation", before)

    preserved_before = machine.succeed(preserved_state_manifest)
    start_and_check_session()
    assert_state_unchanged("M3 daemon startup", preserved_before, preserved_state_manifest)
    stop_user_session_manager()

    # A separately reset home proves pristine initialization without old HM
    # generations, journals, recovery sidecars, or user state leaking in.
    machine.succeed("find /home/lazy -mindepth 1 -delete")
    machine.succeed("chown lazy:users /home/lazy")
    machine.succeed("test -z \"$(find /home/lazy -mindepth 1 -print -quit)\"")
    machine.succeed("test ! -e /home/lazy/.local/state/home-manager")
    machine.succeed(hm_bootstrap)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    machine.succeed("test -s /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("test ! -e /home/lazy/.local/state/home-manager/old-home-manager-generation")
    machine.succeed("! grep -R -F 'VM preserved preset' /home/lazy/.config/sleepy /home/lazy/.local/state/sleepy")
    machine.succeed("grep -F Mod+Shift+Escape /home/lazy/.config/niri/bindings-core.kdl")
    machine.succeed("grep -F toggleControlCenter /home/lazy/.config/niri/sleepy-user-bindings.kdl")

    # A pristine activated profile must start the real M3 daemon under the
    # user manager, publish every private socket, and leave no runtime state
    # behind after its bounded SIGINT shutdown.
    start_and_check_session()
    stop_user_session_manager()

    # Run a genuinely failing initializer in another reset home, rather than
    # merely omitting its output. Static candidate links remain untouched.
    machine.succeed("find /home/lazy -mindepth 1 -delete")
    machine.succeed("chown lazy:users /home/lazy")
    machine.succeed(hm_bootstrap)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    machine.succeed("rm -rf /home/lazy/.config/sleepy /home/lazy/.local/state/sleepy")
    machine.succeed("find /home/lazy/.config/niri -maxdepth 1 -type f \\( -name 'sleepy-user-bindings.kdl' -o -name '.sleepy-user-bindings.kdl.*' \\) -delete")
    machine.fail(f"sudo -u lazy {env} SLEEPY_NIRI_VALIDATOR=/bin/false ${sessionPackage}/bin/sleepyctl bindings initialize")
    machine.succeed("test ! -e /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("test -L /home/lazy/.config/niri/config.kdl")
    machine.succeed("grep -F Mod+Shift+Escape /home/lazy/.config/niri/bindings-core.kdl")
    machine.succeed("${pkgs.niri}/bin/niri validate --config /home/lazy/.config/niri/config.kdl")
  '';
}
