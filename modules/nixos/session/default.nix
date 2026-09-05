{pkgs, ...}: {
  imports = [./pam.nix];

  programs.hyprland = {
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
    # ReGreet has no configurable default session: its fresh fallback is the
    # first HashMap entry. Prefer UWSM without changing saved per-user choices
    # or removing hyprland.desktop, which UWSM needs to launch the compositor.
    displayManager.regreet.package = pkgs.regreet.overrideAttrs (old: {
      postPatch =
        (old.postPatch or "")
        + ''
          substituteInPlace src/gui/component.rs --replace-fail \
            'let mut initial_session = None;' \
            'let mut initial_session = model.sys_util.get_sessions().contains_key("Hyprland (uwsm-managed)").then(|| "Hyprland (uwsm-managed)".to_string());'
        '';
    });
    gnome.gnome-keyring.enable = true;
    greetd.enable = true;
  };

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
    git
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

  systemd.user.services.gnome-keyring-daemon = {
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    after = ["graphical-session.target"];
    requisite = ["graphical-session.target"];
  };
}
