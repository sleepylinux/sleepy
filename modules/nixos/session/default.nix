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
    grim
    jq
    libnotify
    networkmanagerapplet
    ripgrep
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
