{
  config,
  pkgs,
}: let
  ghostty = "${config.programs.ghostty.package}/bin/ghostty";
  firefox = "${config.programs.firefox.package}/bin/firefox";
  ipc = "${config.sleepy.shellPackage}/bin/sleepy-shell-ipc call";
  wpctl = "${pkgs.wireplumber}/bin/wpctl";
  brightnessctl = "${pkgs.brightnessctl}/bin/brightnessctl";
in {
  bind =
    [
      "$mod, Return, exec, ${ghostty}"
      "$mod SHIFT, Return, exec, ${config.programs.foot.package}/bin/foot"
      "$mod, B, exec, ${firefox}"
      "$mod, E, exec, ${pkgs.thunar}/bin/thunar"
      "$mod, D, exec, ${ipc} sleepy toggleLauncher"
      "$mod, C, exec, ${ipc} sleepy toggleDashboard"
      "$mod, V, exec, ${ipc} sleepy toggleNotifications"
      "$mod, N, exec, ${ipc} sleepy toggleNexus"
      "$mod, Escape, exec, ${ipc} sleepy openPowerMenu"
      "$mod, L, exec, ${ipc} sleepy lock"

      "$mod, Q, killactive"
      "$mod, F, fullscreen, 1"
      "$mod, T, togglefloating"
      "$mod, P, pseudo"
      "$mod, J, layoutmsg, togglesplit"
      "$mod, G, togglegroup"

      "$mod, left, movefocus, l"
      "$mod, right, movefocus, r"
      "$mod, up, movefocus, u"
      "$mod, down, movefocus, d"
      "$mod, H, movefocus, l"
      "$mod, K, movefocus, u"

      "$mod SHIFT, left, movewindow, l"
      "$mod SHIFT, right, movewindow, r"
      "$mod SHIFT, up, movewindow, u"
      "$mod SHIFT, down, movewindow, d"

      "$mod, S, togglespecialworkspace, scratchpad"
      "$mod SHIFT, S, movetoworkspacesilent, special:scratchpad"
    ]
    ++ builtins.concatLists (builtins.genList (index: let
        workspace = toString (index + 1);
      in [
        "$mod, ${workspace}, workspace, ${workspace}"
        "$mod SHIFT, ${workspace}, movetoworkspacesilent, ${workspace}"
      ])
      9);

  bindm = [
    "$mod, mouse:272, movewindow"
    "$mod, mouse:273, resizewindow"
  ];

  bindl = [
    ", XF86AudioMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SINK@ toggle"
    ", XF86AudioMicMute, exec, ${wpctl} set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
    ", XF86AudioPlay, exec, ${ipc} sleepy mediaPlayPause"
    ", XF86AudioNext, exec, ${ipc} sleepy mediaNext"
    ", XF86AudioPrev, exec, ${ipc} sleepy mediaPrevious"
  ];

  bindle = [
    ", XF86AudioRaiseVolume, exec, ${wpctl} set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"
    ", XF86AudioLowerVolume, exec, ${wpctl} set-volume @DEFAULT_AUDIO_SINK@ 5%-"
    ", XF86MonBrightnessUp, exec, ${brightnessctl} set +5%"
    ", XF86MonBrightnessDown, exec, ${brightnessctl} set 5%-"
  ];
}
