{
  activationPackage,
  baselineActivationPackage,
  baselineSessionPackage,
  pkgs,
  sessionPackage,
}:
pkgs.testers.runNixOSTest {
  name = "sleepy-niri-to-hyprland-update-safety";

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

    legacy_env = "HOME=/home/lazy XDG_CONFIG_HOME=/home/lazy/.config XDG_STATE_HOME=/home/lazy/.local/state SLEEPY_NIRI_VALIDATOR=${pkgs.niri}/bin/niri"
    state_manifest = "(find /home/lazy/.config/sleepy -xdev -type f -print0 2>/dev/null; find /home/lazy/.local/state/sleepy -xdev -type f ! -name 'bindings-transaction.json' ! -name '.bindings-transaction.json.*' -print0 2>/dev/null; find /home/lazy/.config/niri -maxdepth 1 -type f \\( -name 'sleepy-user-bindings.kdl' -o -name '.sleepy-user-bindings.kdl.*' \\) -print0 2>/dev/null) | sort -z | xargs -0 -r sha256sum"
    preserved_state_manifest = "printf '%s\\0' /home/lazy/.config/sleepy/settings.json /home/lazy/.config/sleepy/themes/11111111-1111-4111-8111-111111111111.json /home/lazy/.config/sleepy/overrides.json /home/lazy/.local/state/sleepy/presets.json /home/lazy/.local/state/sleepy/themes/current.json /home/lazy/.local/state/sleepy/launcher.json /home/lazy/.local/state/sleepy/notifications/active.json /home/lazy/.local/state/sleepy/notifications/archive.json /home/lazy/.local/state/sleepy/notifications/preferences.json /home/lazy/.config/niri/sleepy-user-bindings.kdl | sort -z | xargs -0 sha256sum"
    hm_bootstrap = "install -d -o lazy -g users -m 700 /home/lazy/.local /home/lazy/.local/state /home/lazy/.local/share /home/lazy/.local/state/home-manager /home/lazy/.local/state/nix && install -d -o lazy -g users -m 700 /home/lazy/.local/state/home-manager/gcroots /home/lazy/.local/state/nix/profiles"

    def assert_state_unchanged(label, before, manifest=state_manifest):
        after = machine.succeed(manifest)
        assert after == before, label + " changed user state:\n" + "".join(
            difflib.unified_diff(before.splitlines(keepends=True), after.splitlines(keepends=True))
        )

    def assert_candidate_files():
        machine.succeed("test -L /home/lazy/.config/hypr/hyprland.conf")
        machine.succeed("test -f /home/lazy/.config/hypr/sleepy-user.conf && test ! -L /home/lazy/.config/hypr/sleepy-user.conf")
        machine.succeed("test $(stat -c %a /home/lazy/.config/hypr/sleepy-user.conf) = 600")
        machine.succeed("test -L /home/lazy/.config/uwsm/env")
        for static_name in ["config", "input", "appearance", "bindings-core", "rules", "startup"]:
            machine.succeed(f"test ! -e /home/lazy/.config/niri/{static_name}.kdl && test ! -L /home/lazy/.config/niri/{static_name}.kdl")

    def assert_legacy_niri_preserved():
        machine.succeed("test -f /home/lazy/.config/niri/sleepy-user-bindings.kdl && test ! -L /home/lazy/.config/niri/sleepy-user-bindings.kdl")

    def start_and_check_session():
        machine.succeed("loginctl enable-linger lazy")
        machine.succeed("uid=$(id -u lazy); systemctl start user@$uid.service")
        machine.succeed("uid=$(id -u lazy); install -d -o lazy -g users -m 700 /run/user/$uid/systemd/user && printf '%s\\n' '[Unit]' 'Wants=graphical-session.target' 'After=graphical-session-pre.target' | install -o lazy -g users -m 600 /dev/stdin /run/user/$uid/systemd/user/sleepy-test-session.target")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user mask --runtime sleepy-locker.service")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user daemon-reload")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user start sleepy-test-session.target")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user is-active graphical-session.target")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user start sleepy-session.service")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user is-active sleepy-session.service")
        machine.succeed("uid=$(id -u lazy); test $(sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user show sleepy-session.service -P Type) = notify")
        for socket_name in ["session", "control", "notification", "osd", "daily", "theme", "desktop", "desktop-control", "secret"]:
            machine.wait_until_succeeds(f"uid=$(id -u lazy); test -S /run/user/$uid/sleepy/{socket_name}.sock && test $(stat -c %a /run/user/$uid/sleepy/{socket_name}.sock) = 600")
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user stop sleepy-session.service")
        machine.wait_until_succeeds("uid=$(id -u lazy); test ! -e /run/user/$uid/sleepy")

    def stop_user_session_manager():
        machine.succeed("uid=$(id -u lazy); sudo -u lazy XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user stop sleepy-test-session.target graphical-session.target")
        machine.succeed("uid=$(id -u lazy); systemctl stop user@$uid.service")
        machine.succeed("loginctl disable-linger lazy")
        machine.wait_until_succeeds("uid=$(id -u lazy); test ! -e /run/user/$uid")

    # Establish the previous Niri generation and its user-owned state.
    machine.succeed(hm_bootstrap)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    machine.succeed("test -f /home/lazy/.config/sleepy/settings.json")
    machine.succeed("test -f /home/lazy/.local/state/sleepy/presets.json")
    machine.succeed("test -f /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    for static_name in ["config", "input", "appearance", "bindings-core", "rules", "startup"]:
        machine.succeed(f"test -L /home/lazy/.config/niri/{static_name}.kdl")

    machine.succeed(f"sudo -u lazy {legacy_env} ${baselineSessionPackage}/bin/sleepyctl presets duplicate builtin.sleepy 'VM preserved preset' >/dev/null")
    machine.succeed(f"sudo -u lazy {legacy_env} ${baselineSessionPackage}/bin/sleepyctl bindings reconcile >/dev/null")
    machine.succeed("install -d -o lazy -g users -m 700 /home/lazy/.config/sleepy/themes /home/lazy/.local/state/sleepy/themes /home/lazy/.local/state/sleepy/notifications")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"id\":\"11111111-1111-4111-8111-111111111111\",\"name\":\"VM preserved theme\",\"origin\":\"user\",\"appearance\":\"dark\",\"effects\":\"reduced\",\"reducedMotion\":true,\"opaqueFallback\":false,\"colors\":{\"background\":\"#101010\",\"surface\":\"#181818\",\"textPrimary\":\"#FFFFFF\",\"textSecondary\":\"#E0E0E0\",\"accent\":\"#80BFFF\",\"control\":\"#FFFFFF\"}}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.config/sleepy/themes/11111111-1111-4111-8111-111111111111.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"id\":\"builtin.sleepy-dark\",\"name\":\"Sleepy Dark\",\"origin\":\"builtin\",\"appearance\":\"dark\",\"effects\":\"full\",\"reducedMotion\":false,\"opaqueFallback\":false,\"colors\":{\"background\":\"#10131A\",\"surface\":\"#181D27\",\"textPrimary\":\"#F7F9FC\",\"textSecondary\":\"#D8DEE9\",\"accent\":\"#8EC5FF\",\"control\":\"#F7F9FC\"}}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/themes/current.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"overrides\":{\"weatherEndpoint\":\"https://example.invalid/weather\"}}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.config/sleepy/overrides.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"entries\":{\"org.example.App.desktop\":{\"count\":3,\"lastUsed\":42}}}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/launcher.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"notifications\":[{\"schemaVersion\":2,\"id\":11,\"applicationId\":\"org.example.Active\",\"summary\":\"Message 11\",\"body\":\"Preserve active\",\"urgency\":\"normal\",\"createdAt\":\"2026-08-24T21:00:00Z\",\"timeoutMs\":5000,\"read\":false,\"archived\":false,\"actions\":[]}]}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/notifications/active.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"notifications\":[]}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/notifications/archive.json")
    machine.succeed("printf '%s\\n' '{\"schemaVersion\":1,\"dnd\":true,\"nextNotificationId\":20}' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.local/state/sleepy/notifications/preferences.json")

    before = machine.succeed(state_manifest)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert_state_unchanged("Niri to Hyprland activation", before)
    assert_candidate_files()
    assert_legacy_niri_preserved()
    override_before = machine.succeed("sha256sum /home/lazy/.config/hypr/sleepy-user.conf")

    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert_state_unchanged("repeat Hyprland activation", before)
    assert machine.succeed("sha256sum /home/lazy/.config/hypr/sleepy-user.conf") == override_before

    # Re-activating the previous generation restores its managed Niri files
    # while preserving every user-owned document byte-for-byte.
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    assert_state_unchanged("rollback activation", before)
    for static_name in ["config", "input", "appearance", "bindings-core", "rules", "startup"]:
        machine.succeed(f"test -L /home/lazy/.config/niri/{static_name}.kdl")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert_state_unchanged("return to Hyprland activation", before)
    assert_candidate_files()
    assert_legacy_niri_preserved()

    preserved_before = machine.succeed(preserved_state_manifest)
    start_and_check_session()
    assert_state_unchanged("M3 daemon startup", preserved_before, preserved_state_manifest)
    stop_user_session_manager()

    # A pristine home receives only immutable candidate links and an empty,
    # private user override. Niri is not recreated by the candidate graph.
    machine.succeed("find /home/lazy -mindepth 1 -delete")
    machine.succeed("chown lazy:users /home/lazy")
    machine.succeed(hm_bootstrap)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert_candidate_files()
    machine.succeed("test ! -e /home/lazy/.config/niri")
    machine.succeed("test ! -e /home/lazy/.config/sleepy/settings.json")
    machine.succeed("test ! -e /home/lazy/.local/state/sleepy/presets.json")
    machine.succeed("test ! -e /home/lazy/.local/state/home-manager/old-home-manager-generation")

    machine.succeed("printf '%s\\n' '# preserved user override' | install -o lazy -g users -m 600 /dev/stdin /home/lazy/.config/hypr/sleepy-user.conf")
    pristine_override = machine.succeed("sha256sum /home/lazy/.config/hypr/sleepy-user.conf")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert machine.succeed("sha256sum /home/lazy/.config/hypr/sleepy-user.conf") == pristine_override

    # A hostile symlink at the mutable override path must make activation fail
    # without following the link or corrupting its target.
    machine.succeed("printf '%s\\n' protected > /home/lazy/protected-override && chown lazy:users /home/lazy/protected-override")
    machine.succeed("rm /home/lazy/.config/hypr/sleepy-user.conf && ln -s /home/lazy/protected-override /home/lazy/.config/hypr/sleepy-user.conf && chown -h lazy:users /home/lazy/.config/hypr/sleepy-user.conf")
    machine.fail("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    machine.succeed("test $(cat /home/lazy/protected-override) = protected")
    machine.succeed("rm /home/lazy/.config/hypr/sleepy-user.conf")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert_candidate_files()

    start_and_check_session()
    stop_user_session_manager()
  '';
}
