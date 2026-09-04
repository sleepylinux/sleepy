{
  "$mod" = "SUPER";
  "$terminal" = "ghostty";
  "$browser" = "firefox";

  monitor = [",preferred,auto,1"];

  env = [
    "XDG_CURRENT_DESKTOP,Hyprland"
    "XDG_SESSION_DESKTOP,Hyprland"
    "QT_QPA_PLATFORM,wayland;xcb"
    "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
    "GDK_BACKEND,wayland,x11,*"
    "MOZ_ENABLE_WAYLAND,1"
    "SDL_VIDEODRIVER,wayland"
    "XCURSOR_SIZE,24"
    "HYPRCURSOR_SIZE,24"
  ];

  input = {
    kb_layout = "us,ru";
    kb_options = "grp:alt_shift_toggle";
    follow_mouse = 1;
    mouse_refocus = false;
    sensitivity = 0;
    accel_profile = "flat";

    touchpad = {
      natural_scroll = true;
      disable_while_typing = true;
      clickfinger_behavior = true;
      tap-to-click = true;
    };
  };

  gesture = ["3, horizontal, workspace"];

  dwindle = {
    preserve_split = true;
    smart_split = false;
  };

  group = {
    insert_after_current = true;
    focus_removed_window = true;
    groupbar = {
      enabled = true;
      font_size = 10;
      gradients = true;
      height = 14;
    };
  };

  misc = {
    disable_hyprland_logo = true;
    disable_splash_rendering = true;
    force_default_wallpaper = 0;
    focus_on_activate = true;
  };
}
