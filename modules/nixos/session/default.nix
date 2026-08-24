{pkgs, ...}: {
  programs.niri.enable = true;

  services = {
    displayManager.regreet.enable = true;
    greetd.enable = true;
  };

  environment.systemPackages = with pkgs; [
    git
    grim
    jq
    libnotify
    networkmanagerapplet
    quickshell
    ripgrep
    wl-clipboard
    xwayland-satellite
  ];

  systemd.user.services.polkit-gnome-authentication-agent-1 = {
    description = "PolicyKit Authentication Agent";
    wantedBy = ["graphical-session.target"];
    partOf = ["graphical-session.target"];
    after = ["graphical-session.target"];
    requisite = ["graphical-session.target"];
    serviceConfig.ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
  };
}
