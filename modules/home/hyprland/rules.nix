{config}: {
  workspace = [
    "special:scratchpad, on-created-empty:${config.programs.ghostty.package}/bin/ghostty"
  ];

  windowrule = [
    "float on, match:class ^(org.gnome.Calculator)$"
    "float on, match:class ^(org.pulseaudio.pavucontrol)$"
    "float on, match:class ^(blueman-manager)$"
    "float on, match:title ^(Picture-in-Picture)$"
    "pin on, match:title ^(Picture-in-Picture)$"
    "size 60% 65%, match:class ^(org.pulseaudio.pavucontrol)$"
    "center on, match:class ^(org.pulseaudio.pavucontrol)$"
    "suppress_event maximize, match:class .*"
  ];

  layerrule = [
    "blur on, match:namespace quickshell"
    "ignore_alpha 0.20, match:namespace quickshell"
  ];
}
