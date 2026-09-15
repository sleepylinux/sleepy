{
  config,
  lib,
  pkgs,
  ...
}: let
  # Keep the raw entry available for UWSM's desktop-file lookup, but don't
  # offer a login path which bypasses the graphical session's services.
  loginSessions =
    pkgs.runCommand "sleepy-login-sessions" {
      passthru.providedSessions = ["hyprland-uwsm"];
    } ''
      mkdir -p "$out/share/wayland-sessions"
      cp ${config.programs.hyprland.package}/share/wayland-sessions/hyprland{,-uwsm}.desktop \
        "$out/share/wayland-sessions/"
      chmod u+w "$out/share/wayland-sessions/hyprland.desktop"
      substituteInPlace "$out/share/wayland-sessions/hyprland.desktop" \
        --replace-fail '[Desktop Entry]' $'[Desktop Entry]\nNoDisplay=true'
    '';
in {
  imports = [./pam.nix];

  programs.hyprland = {
    package = lib.mkDefault (import ../../../packages/vendor/hyprland-session-redraw {inherit pkgs;});
    enable = true;
    xwayland.enable = true;
    withUWSM = true;
  };
  programs.uwsm.enable = true;

  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.UPower.PowerProfiles.switch-profile" &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  services = {
    displayManager.regreet.enable = true;
    # The standard session-data directory comes first in XDG_DATA_DIRS.
    # ReGreet honors NoDisplay there, including duplicate package entries.
    displayManager.sessionPackages = lib.mkForce [loginSessions];
    gnome.gnome-keyring.enable = true;
    greetd.enable = true;
  };

  services.displayManager.regreet.settings.GTK.application_prefer_dark_theme = lib.mkDefault true;

  security.pam.services.greetd.enableGnomeKeyring = true;

  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-hyprland
      pkgs.xdg-desktop-portal-gtk
    ];
    config = {
      common = {
        default = ["hyprland" "gtk"];
        "org.freedesktop.impl.portal.FileChooser" = ["gtk"];
        "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
        "org.freedesktop.impl.portal.Screenshot" = ["hyprland"];
      };
      Hyprland = {
        default = ["hyprland" "gtk"];
        "org.freedesktop.impl.portal.FileChooser" = ["gtk"];
        "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
        "org.freedesktop.impl.portal.Screenshot" = ["hyprland"];
      };
    };
  };

  environment.systemPackages = with pkgs; [
    bluez
    brightnessctl
    ddcutil
    grim
    jq
    libqalculate
    libnotify
    lm_sensors
    networkmanagerapplet
    power-profiles-daemon
    ripgrep
    swappy
    wireplumber
    wl-clipboard
    cliphist
  ];

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "PolicyKit Authentication Agent";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    after = ["graphical-session.target"];
    requisite = ["graphical-session.target"];
    serviceConfig.ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
  };

  # Upstream GNOME Keyring uses PAM login unlock and DBus activation. It does
  # not define a systemd user service to extend; an ordering-only unit is invalid.
}
