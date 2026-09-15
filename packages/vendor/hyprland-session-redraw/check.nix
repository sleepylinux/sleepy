{pkgs}:
assert pkgs.hyprland.version == "0.56.2";
  pkgs.runCommand "hyprland-session-activation-frame" {
    nativeBuildInputs = [pkgs.gcc pkgs.python3 pkgs.patch];
  } ''
    mkdir -p "$out" source/src/output
    cp ${pkgs.hyprland.src}/src/Compositor.cpp source/src/
    cp ${pkgs.hyprland.src}/src/output/Monitor.cpp source/src/output/
    python3 ${./test-activation.py} source --expect-broken > "$out/red.log"
    patch -d source -p1 < ${./session-activation-redraw.patch}
    python3 ${./test-activation.py} source > "$out/green.log"
  ''
