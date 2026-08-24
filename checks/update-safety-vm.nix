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
    state_manifest = "(find /home/lazy/.config/sleepy /home/lazy/.local/state/sleepy -xdev -type f -print0 2>/dev/null; find /home/lazy/.config/niri -maxdepth 1 -type f \\( -name 'sleepy-user-bindings.kdl' -o -name '.sleepy-user-bindings.kdl.*' \\) -print0 2>/dev/null) | sort -z | xargs -0 -r sha256sum"

    # Historical activation is the first writer in this isolated VM home.
    machine.succeed("test ! -e /home/lazy/.config/sleepy/settings.json")
    machine.succeed("test ! -e /home/lazy/.local/state/sleepy/presets.json")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    machine.succeed("test ! -e /home/lazy/.config/sleepy/settings.json")
    machine.succeed("test ! -e /home/lazy/.local/state/sleepy/presets.json")
    machine.succeed("test ! -e /home/lazy/.config/niri/sleepy-user-bindings.kdl")

    # Seed user state only after the exact old activation. The first binding
    # transaction is activation --apply against the complete candidate tree.
    machine.succeed("rm -f /home/lazy/.config/niri/*.kdl")
    machine.succeed("cp ${source}/modules/home/niri/config/*.kdl /home/lazy/.config/niri/")
    machine.succeed("chown -R lazy:users /home/lazy/.config /home/lazy/.local")
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl settings show >/dev/null")
    duplicate = machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl presets duplicate builtin.sleepy 'VM preserved preset'")
    preset_id = json.loads(duplicate)["preset"]["id"]
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl presets activate {preset_id} --apply >/dev/null")

    before = machine.succeed(state_manifest)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    assert machine.succeed(state_manifest) == before
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert machine.succeed(state_manifest) == before
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl bindings reconcile >/dev/null")
    assert machine.succeed(state_manifest) == before

    # A separately reset home proves pristine initialization without old HM
    # generations, journals, recovery sidecars, or user state leaking in.
    machine.succeed("find /home/lazy -mindepth 1 -delete")
    machine.succeed("chown lazy:users /home/lazy")
    machine.succeed("test -z \"$(find /home/lazy -mindepth 1 -print -quit)\"")
    machine.succeed("test ! -e /home/lazy/.local/state/home-manager")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    machine.succeed("test -s /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("test ! -e /home/lazy/.local/state/home-manager/old-home-manager-generation")
    machine.succeed("! grep -R -F 'VM preserved preset' /home/lazy/.config/sleepy /home/lazy/.local/state/sleepy")
    machine.succeed("grep -F Mod+Shift+Escape /home/lazy/.config/niri/bindings-core.kdl")
    machine.succeed("grep -F toggleControlCenter /home/lazy/.config/niri/sleepy-user-bindings.kdl")

    # Simulate initializer failure in another fully reset home. Optional user
    # bindings plus immutable recovery must still make the root config valid.
    machine.succeed("find /home/lazy -mindepth 1 -delete")
    machine.succeed("install -d -o lazy -g users /home/lazy/.config/niri")
    machine.succeed("cp ${source}/modules/home/niri/config/*.kdl /home/lazy/.config/niri/")
    machine.succeed("rm -f /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("test ! -e /home/lazy/.config/sleepy && test ! -e /home/lazy/.local/state/sleepy")
    machine.succeed("grep -F Mod+Shift+Escape /home/lazy/.config/niri/bindings-core.kdl")
    machine.succeed("${pkgs.niri}/bin/niri validate --config /home/lazy/.config/niri/config.kdl")
  '';
}
