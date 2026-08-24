{
  activationPackage,
  baselineActivationPackage,
  pkgs,
  sessionPackage,
  source,
}:
pkgs.testers.runNixOSTest {
  name = "sleepy-m1-to-m2-update-safety";

  nodes.machine = {pkgs, ...}: {
    users.users.lazy = {
      isNormalUser = true;
      home = "/home/lazy";
    };
    environment.systemPackages = [pkgs.jq pkgs.niri sessionPackage];
  };

  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    env = "HOME=/home/lazy XDG_CONFIG_HOME=/home/lazy/.config XDG_STATE_HOME=/home/lazy/.local/state SLEEPY_NIRI_VALIDATOR=${pkgs.niri}/bin/niri"
    machine.succeed("install -d -o lazy -g users /home/lazy/.config/niri /home/lazy/.local/state")
    machine.succeed("cp ${source}/modules/home/niri/config/*.kdl /home/lazy/.config/niri/")
    machine.succeed("chown -R lazy:users /home/lazy/.config /home/lazy/.local")
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl settings show >/dev/null")
    duplicate = machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl presets duplicate builtin.sleepy 'VM preserved preset'")
    preset_id = json.loads(duplicate)["preset"]["id"]
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl presets activate {preset_id} --apply >/dev/null")

    mutable = "/home/lazy/.config/sleepy/settings.json /home/lazy/.local/state/sleepy/presets.json /home/lazy/.config/niri/sleepy-user-bindings.kdl"
    before = machine.succeed(f"sha256sum {mutable}")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    assert machine.succeed(f"sha256sum {mutable}") == before
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert machine.succeed(f"sha256sum {mutable}") == before
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl bindings reconcile >/dev/null")
    assert machine.succeed(f"sha256sum {mutable}") == before

    machine.succeed("rm -f /home/lazy/.config/sleepy/settings.json /home/lazy/.local/state/sleepy/presets.json /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    machine.succeed("test -s /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("grep -F Mod+Shift+Escape /home/lazy/.config/niri/bindings-core.kdl")
    machine.succeed("grep -F toggleControlCenter /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("rm -f /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("${pkgs.niri}/bin/niri validate --config /home/lazy/.config/niri/config.kdl")
  '';
}
