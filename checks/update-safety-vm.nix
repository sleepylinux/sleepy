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
    virtualisation.additionalPaths = [baselineActivationPackage activationPackage];
  };

  testScript = ''
    import json

    start_all()
    machine.wait_for_unit("multi-user.target")

    env = "HOME=/home/lazy XDG_CONFIG_HOME=/home/lazy/.config XDG_STATE_HOME=/home/lazy/.local/state SLEEPY_NIRI_VALIDATOR=${pkgs.niri}/bin/niri"
    state_manifest = "(find /home/lazy/.config/sleepy /home/lazy/.local/state/sleepy -xdev -type f -print0 2>/dev/null; find /home/lazy/.config/niri -maxdepth 1 -type f \\( -name 'sleepy-user-bindings.kdl' -o -name '.sleepy-user-bindings.kdl.*' \\) -print0 2>/dev/null) | sort -z | xargs -0 -r sha256sum"
    hm_bootstrap = "install -d -o lazy -g users -m 700 /home/lazy/.local /home/lazy/.local/state /home/lazy/.local/share /home/lazy/.local/state/home-manager /home/lazy/.local/state/nix && install -d -o lazy -g users -m 700 /home/lazy/.local/state/home-manager/gcroots /home/lazy/.local/state/nix/profiles"

    # Historical activation is the first writer in this isolated VM home.
    machine.succeed("test ! -e /home/lazy/.config/sleepy/settings.json")
    machine.succeed("test ! -e /home/lazy/.local/state/sleepy/presets.json")
    machine.succeed(hm_bootstrap)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    machine.succeed("test ! -e /home/lazy/.config/sleepy/settings.json")
    machine.succeed("test ! -e /home/lazy/.local/state/sleepy/presets.json")
    machine.succeed("test ! -e /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    for static_name in ["config", "input", "appearance", "bindings", "rules", "startup"]:
        machine.succeed(f"test -L /home/lazy/.config/niri/{static_name}.kdl")

    # Seed only user-owned files. Historical Home Manager links remain intact
    # until the candidate generation legitimately replaces them.
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl settings show >/dev/null")
    duplicate = machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl presets duplicate builtin.sleepy 'VM preserved preset'")
    preset_id = json.loads(duplicate)["preset"]["id"]
    machine.succeed(f"${pkgs.jq}/bin/jq --arg id {preset_id} '.activePresetId = $id' /home/lazy/.config/sleepy/settings.json > /tmp/sleepy-settings.json && install -o lazy -g users -m 600 /tmp/sleepy-settings.json /home/lazy/.config/sleepy/settings.json")
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl bindings render > /tmp/sleepy-render.json")
    machine.succeed("${pkgs.jq}/bin/jq -j .kdl /tmp/sleepy-render.json > /tmp/sleepy-user-bindings.kdl && install -o lazy -g users -m 600 /tmp/sleepy-user-bindings.kdl /home/lazy/.config/niri/sleepy-user-bindings.kdl")
    machine.succeed("test ! -e /home/lazy/.local/state/sleepy/bindings-transaction.json")

    before = machine.succeed(state_manifest)
    machine.succeed("sudo -u lazy HOME=/home/lazy ${baselineActivationPackage}/activate")
    assert machine.succeed(state_manifest) == before
    for static_name in ["config", "input", "appearance", "bindings", "rules", "startup"]:
        machine.succeed(f"test -L /home/lazy/.config/niri/{static_name}.kdl")
    machine.succeed("sudo -u lazy HOME=/home/lazy ${activationPackage}/activate")
    assert machine.succeed(state_manifest) == before
    for static_name in ["config", "input", "appearance", "bindings-core", "rules", "startup"]:
        machine.succeed(f"test -L /home/lazy/.config/niri/{static_name}.kdl")
    machine.succeed("test ! -e /home/lazy/.config/niri/bindings.kdl")
    machine.succeed(f"sudo -u lazy {env} ${sessionPackage}/bin/sleepyctl bindings reconcile >/dev/null")
    assert machine.succeed(state_manifest) == before

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
