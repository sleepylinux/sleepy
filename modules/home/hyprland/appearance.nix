{
  general = {
    gaps_in = 5;
    gaps_out = 10;
    border_size = 2;
    resize_on_border = true;
    extend_border_grab_area = 12;
    layout = "dwindle";
    "col.active_border" = "rgba(b9a7ffff) rgba(82aaffff) 45deg";
    "col.inactive_border" = "rgba(5d526f99)";
  };

  decoration = {
    rounding = 14;
    rounding_power = 2;
    active_opacity = 1.0;
    inactive_opacity = 0.96;
    fullscreen_opacity = 1.0;

    blur = {
      enabled = true;
      size = 8;
      passes = 3;
      ignore_opacity = true;
      new_optimizations = true;
      vibrancy = 0.18;
    };

    shadow = {
      enabled = true;
      range = 18;
      render_power = 3;
      color = "rgba(11111bcc)";
    };
  };

  animations = {
    enabled = true;
    bezier = [
      "sleepy,0.22,1,0.36,1"
      "sleepyOut,0.4,0,1,1"
    ];
    animation = [
      "windows,1,5,sleepy,popin 85%"
      "windowsOut,1,4,sleepyOut,popin 85%"
      "border,1,6,sleepy"
      "fade,1,4,sleepy"
      "workspaces,1,5,sleepy,slide"
      "specialWorkspace,1,5,sleepy,slidevert"
    ];
  };
}
