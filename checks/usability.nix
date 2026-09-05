{
  pkgs,
  nixosConfig,
  homeConfig,
}: let
  inherit (pkgs) lib;
  settings = homeConfig.wayland.windowManager.hyprland.settings;
  hasBind = kind: binding: builtins.elem binding (settings.${kind} or []);
  wpctl = "${pkgs.wireplumber}/bin/wpctl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
  greeter = nixosConfig.services.displayManager.regreet.package;
  sessions = lib.concatMap (package: package.providedSessions or []) nixosConfig.services.displayManager.sessionPackages;
in
  assert lib.assertMsg
  (nixosConfig.programs.hyprland.package
    == pkgs.hyprland
    && homeConfig.wayland.windowManager.hyprland.package == null
    && builtins.elem ../patches/hyprland-session-lock-vt-focus.patch (pkgs.hyprland.patches or []))
  "NixOS must own the patched compositor without a competing Home Manager package";
  assert lib.assertMsg
  (nixosConfig.programs.hyprland.withUWSM
    && lib.hasInfix "Hyprland (uwsm-managed)" (greeter.postPatch or "")
    && lib.hasInfix (builtins.unsafeDiscardStringContext (lib.getExe greeter)) nixosConfig.services.greetd.settings.default_session.command)
  "ReGreet must prefer the UWSM-managed session for fresh logins";
  assert lib.assertMsg
  (builtins.elem "hyprland" sessions && builtins.elem "hyprland-uwsm" sessions)
  "Both the managed login and its underlying Hyprland session must remain installed";
  assert lib.assertMsg
  (lib.all (feature: builtins.elem feature (nixosConfig.nix.settings.experimental-features or [])) ["nix-command" "flakes"])
  "Sleepy must enable the Nix command and flakes";
  assert lib.assertMsg
  (nixosConfig.services.gvfs.enable && nixosConfig.services.udisks2.enable)
  "Sleepy must support browsing and mounting removable media";
  assert lib.assertMsg
  (builtins.elem pkgs.thunar homeConfig.home.packages
    && homeConfig.xdg.mimeApps.enable
    && homeConfig.xdg.mimeApps.defaultApplications."inode/directory" == ["thunar.desktop"])
  "Sleepy must install Thunar and use it to open directories";
  assert lib.assertMsg
  (hasBind "bind" "$mod, E, exec, ${pkgs.thunar}/bin/thunar")
  "Sleepy must provide a file manager shortcut";
  assert lib.assertMsg
  (homeConfig.programs.foot.enable
    && hasBind "bind" "$mod SHIFT, Return, exec, ${homeConfig.programs.foot.package}/bin/foot")
  "Sleepy must provide an accessible terminal fallback for limited graphics hardware";
  assert lib.assertMsg
  (lib.all (hasBind "bindle") [
    ", XF86AudioRaiseVolume, exec, ${wpctl} set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
    ", XF86AudioLowerVolume, exec, ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ", XF86MonBrightnessUp, exec, ${brightnessctl} set +5%"
    ", XF86MonBrightnessDown, exec, ${brightnessctl} set 5%-"
  ])
  "Sleepy must provide repeatable volume and brightness shortcuts with packaged tools";
  assert lib.assertMsg
  (lib.all (hasBind "bindl") [
    ", XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ", XF86AudioMicMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
  ])
  "Sleepy must provide speaker and microphone mute shortcuts";
    pkgs.runCommand "sleepy-usability" {nativeBuildInputs = [pkgs.python3];} ''
      cp -r ${greeter.src} regreet-source
      chmod -R u+w regreet-source
      cd regreet-source
      ${greeter.postPatch or ""}
      python3 - <<'PY'
      from pathlib import Path
      original = Path('${greeter.src}/src/gui/component.rs').read_text()
      patched = Path('src/gui/component.rs').read_text()
      old = 'let mut initial_session = None;'
      new = 'let mut initial_session = model.sys_util.get_sessions().contains_key("Hyprland (uwsm-managed)").then(|| "Hyprland (uwsm-managed)".to_string());'
      assert original.count(old) == 1
      # Only the initial fallback changes: cache precedence and all session entries survive.
      assert patched == original.replace(old, new)
      assert 'if !model.cache.has_last_session(user)' in patched
      assert 'for session in model.sys_util.get_sessions().keys()' in patched
      assert 'if initial_session.is_none()' in patched
      PY
      touch "$out"
    ''
