{config}: let
  ghostty = "${config.programs.ghostty.package}/bin/ghostty";
  firefox = "${config.programs.firefox.package}/bin/firefox";
  ipc = "${config.sleepy.shellPackage}/bin/sleepy-shell-ipc call";
in {
  bind =
    [
      "$mod, Return, exec, ${ghostty}"
      "$mod, B, exec, ${firefox}"
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
    ", XF86AudioPlay, exec, ${ipc} sleepy mediaPlayPause"
    ", XF86AudioNext, exec, ${ipc} sleepy mediaNext"
    ", XF86AudioPrev, exec, ${ipc} sleepy mediaPrevious"
  ];
}
