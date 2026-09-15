{
  config,
  pkgs,
}: let
  wantedServices = builtins.attrNames (pkgs.lib.filterAttrs
    (_: service: service.enable && service.wantedBy != [])
    config.systemd.user.services);
  userUnits = config.environment.etc."systemd/user".source;
in
  assert pkgs.lib.assertMsg (!(config.systemd.user.services ? gnome-keyring-daemon))
  "GNOME Keyring must use upstream PAM and DBus activation, not an incomplete custom unit";
  assert pkgs.lib.assertMsg
  (config.services.gnome.gnome-keyring.enable
    && config.security.pam.services.greetd.enableGnomeKeyring
    && config.security.pam.services.login.enableGnomeKeyring
    && builtins.elem pkgs.gnome-keyring config.services.dbus.packages
    && builtins.elem pkgs.gcr config.services.dbus.packages
    && config.security.wrappers.gnome-keyring-daemon.source == "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon")
  "keyring must retain upstream login unlock, Secret Service activation and its capability wrapper";
    pkgs.runCommand "sleepy-keyring-contract" {
      nativeBuildInputs = [pkgs.gnugrep];
    } ''
      set -eu
      # Inspect the assembled unit directory, including package-provided base units.
      # NixOS unit.text alone can be an ordering/environment-only drop-in.
      for service in ${pkgs.lib.escapeShellArgs wantedServices}; do
        executable=0
        for unit in ${userUnits}/"$service.service" ${userUnits}/"$service.service.d/"*.conf; do
          if test -f "$unit" && grep -Eq '^ExecStart=.+$' "$unit"; then executable=1; fi
        done
        test "$executable" = 1 || {
          echo "wanted user service has no executable start: $service" >&2
          exit 1
        }
      done
      test ! -e ${userUnits}/gnome-keyring-daemon.service
      grep -E '^auth .*pam_gnome_keyring\.so' ${config.environment.etc."pam.d/login".source}
      grep -E '^session .*pam_gnome_keyring\.so.*auto_start' ${config.environment.etc."pam.d/login".source}
      grep -F 'Name=org.freedesktop.secrets' ${pkgs.gnome-keyring}/share/dbus-1/services/org.freedesktop.secrets.service
      touch "$out"
    ''
