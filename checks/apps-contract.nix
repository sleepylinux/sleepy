{
  extendStandaloneHome,
  integratedHomeConfig,
  nixosConfig,
  pkgs,
  standaloneHomeConfig,
}: let
  integratedGhostty = integratedHomeConfig.programs.ghostty.package;
  standaloneGhostty = standaloneHomeConfig.programs.ghostty.package;
  expectedIntegratedTerminal = "${integratedGhostty}/bin/ghostty";
  expectedStandaloneTerminal = "${standaloneGhostty}/bin/ghostty";
  overridden =
    (extendStandaloneHome {
      modules = [
        {
          programs.fastfetch.settings = {
            logo.source = "/fixture/custom-logo.txt";
            display.color.keys = "blue";
            modules = ["os"];
          };
          programs.ghostty.settings.background = "202020";
          programs.fuzzel.settings.main.width = 42;
          programs.swappy.settings.Default.save_dir = "/fixture/Captures";
          xdg.mimeApps.defaultApplications."image/png" = ["fixture-viewer.desktop"];
          gtk.theme.name = "Fixture GTK theme";
          gtk.iconTheme.name = "Fixture icons";
          dconf.settings."org/gnome/desktop/interface".color-scheme = "default";
        }
      ];
    }).config;
  disabled =
    (extendStandaloneHome {
      modules = [
        {
          programs.fastfetch.enable = false;
          programs.imv.enable = false;
          gtk.enable = false;
        }
      ];
    }).config;
  customPictures =
    (extendStandaloneHome {
      modules = [{xdg.userDirs.pictures = "/fixture/Pictures";}];
    }).config;
  withoutPictures =
    (extendStandaloneHome {
      modules = [{xdg.userDirs.pictures = null;}];
    }).config;
  # Evaluate real Home Manager merges, including option normalization, rather
  # than checking source spelling or copying the module's merge implementation.
  moduleChecks = {
    fastfetchEnabledByDefault = standaloneHomeConfig.programs.fastfetch.enable;
    fastfetchConfigGenerated = standaloneHomeConfig.xdg.configFile ? "fastfetch/config.jsonc";
    fastfetchDisableRemovesConfig = !(disabled.xdg.configFile ? "fastfetch/config.jsonc");
    fastfetchDisableRemovesPackage =
      !(builtins.elem
        (toString standaloneHomeConfig.programs.fastfetch.package)
        (map toString disabled.home.packages));
    logoSourceOverride = overridden.programs.fastfetch.settings.logo.source == "/fixture/custom-logo.txt";
    logoTypePreserved = overridden.programs.fastfetch.settings.logo.type == standaloneHomeConfig.programs.fastfetch.settings.logo.type;
    logoPalettePreserved = overridden.programs.fastfetch.settings.logo.color == standaloneHomeConfig.programs.fastfetch.settings.logo.color;
    displayColorOverride = overridden.programs.fastfetch.settings.display.color.keys == "blue";
    displayTitlePreserved = overridden.programs.fastfetch.settings.display.color.title == standaloneHomeConfig.programs.fastfetch.settings.display.color.title;
    moduleListReplacesDefaults = overridden.programs.fastfetch.settings.modules == ["os"];
    # The pinned Ghostty module normalizes scalar options into lists.
    ghosttyBackgroundOverride = overridden.programs.ghostty.settings.background == ["202020"];
    ghosttyForegroundPreserved = overridden.programs.ghostty.settings.foreground == standaloneHomeConfig.programs.ghostty.settings.foreground;
    ghosttyCommandPreserved = overridden.programs.ghostty.settings.command == standaloneHomeConfig.programs.ghostty.settings.command;
    fuzzelWidthOverride = overridden.programs.fuzzel.settings.main.width == 42;
    fuzzelPalettePreserved = overridden.programs.fuzzel.settings.colors == standaloneHomeConfig.programs.fuzzel.settings.colors;
    gtkThemeOverride = overridden.gtk.theme.name == "Fixture GTK theme";
    gtkIconOverride = overridden.gtk.iconTheme.name == "Fixture icons";
    gtkDarkDefaultPreserved = overridden.gtk.gtk3.extraConfig.gtk-application-prefer-dark-theme;
    gtkDisableHonored = !disabled.gtk.enable;
    gtkDisableRemovesConfig = !(disabled.xdg.configFile ? "gtk-3.0/settings.ini");
    dconfColorSchemeOverride = overridden.dconf.settings."org/gnome/desktop/interface".color-scheme == "default";
    integratedFastfetchEnabled = integratedHomeConfig.programs.fastfetch.enable;
    integratedGtkThemeEnabled = integratedHomeConfig.gtk.enable && integratedHomeConfig.gtk.theme.name == "adw-gtk3-dark";
    integratedGhosttyPalette = integratedHomeConfig.programs.ghostty.settings.foreground == standaloneHomeConfig.programs.ghostty.settings.foreground;
    swappyEnabledByDefault = standaloneHomeConfig.programs.swappy.enable;
    swappySaveDirectoryOverride = overridden.programs.swappy.settings.Default.save_dir == "/fixture/Captures";
    swappyFilenamePreserved = overridden.programs.swappy.settings.Default.save_filename_format == standaloneHomeConfig.programs.swappy.settings.Default.save_filename_format;
    swappyUsesPicturesDirectory = customPictures.programs.swappy.settings.Default.save_dir == "/fixture/Pictures/Screenshots";
    swappyNullPicturesFallback = withoutPictures.programs.swappy.settings.Default.save_dir == "${standaloneHomeConfig.home.homeDirectory}/Pictures/Screenshots";
    imageViewerDefault = standaloneHomeConfig.programs.imv.enable && standaloneHomeConfig.xdg.mimeApps.defaultApplications."image/png" == ["imv.desktop"];
    imageViewerOverride = overridden.xdg.mimeApps.defaultApplications."image/png" == ["fixture-viewer.desktop"];
    imageViewerDisableRemovesMimeDefault = !(disabled.xdg.mimeApps.defaultApplications ? "image/png");
    imageViewerDisableRemovesPackage =
      !(builtins.elem
        (toString standaloneHomeConfig.programs.imv.package)
        (map toString disabled.home.packages));
  };
in
  assert pkgs.lib.all
  (name: pkgs.lib.assertMsg moduleChecks.${name} "Sleepy app module contract failed: ${name}")
  (builtins.attrNames moduleChecks);
  assert pkgs.lib.assertMsg
  (integratedGhostty != pkgs.ghostty)
  "Sleepy VM must use its renderer-compatible Ghostty package";
  assert pkgs.lib.assertMsg
  (standaloneGhostty == pkgs.ghostty)
  "standalone Home Manager must keep the unwrapped Ghostty package";
  assert pkgs.lib.assertMsg
  (integratedHomeConfig.programs.fuzzel.settings.main.terminal == expectedIntegratedTerminal)
  "integrated Fuzzel must use the final configured Ghostty package";
  assert pkgs.lib.assertMsg
  (standaloneHomeConfig.programs.fuzzel.settings.main.terminal == expectedStandaloneTerminal)
  "standalone Fuzzel must use the final configured Ghostty package";
  assert pkgs.lib.assertMsg
  (!(integratedHomeConfig.home.sessionVariables ? LIBGL_ALWAYS_SOFTWARE))
  "Home Manager must not export LIBGL_ALWAYS_SOFTWARE at session scope";
  assert pkgs.lib.assertMsg
  (!(standaloneHomeConfig.home.sessionVariables ? LIBGL_ALWAYS_SOFTWARE))
  "standalone Home Manager must not export LIBGL_ALWAYS_SOFTWARE at session scope";
  assert pkgs.lib.assertMsg
  (!(nixosConfig.environment.variables ? LIBGL_ALWAYS_SOFTWARE))
  "NixOS must not export LIBGL_ALWAYS_SOFTWARE globally";
  assert pkgs.lib.assertMsg
  (!(nixosConfig.environment.sessionVariables ? LIBGL_ALWAYS_SOFTWARE))
  "NixOS must not export LIBGL_ALWAYS_SOFTWARE at session scope";
    pkgs.runCommand "sleepy-apps-contract" {
      nativeBuildInputs = [pkgs.gnugrep];
    } ''
      set -eu

      wrapper=${integratedGhostty}/bin/ghostty
      standalone=${standaloneGhostty}/bin/ghostty

      test -x "$wrapper"
      test ! -L "$wrapper"
      test -x "$standalone"

      ${pkgs.gnugrep}/bin/grep -Fx "export LIBGL_ALWAYS_SOFTWARE='1'" "$wrapper"
      test "$(${pkgs.gnugrep}/bin/grep -c '^export [A-Za-z_][A-Za-z0-9_]*=' "$wrapper")" -eq 1
      ! ${pkgs.gnugrep}/bin/grep -q 'LIBGL_ALWAYS_SOFTWARE' "$standalone"

      wrapped_version=$("$wrapper" --version)
      standalone_version=$("$standalone" --version)
      test "$wrapped_version" = "$standalone_version"

      touch "$out"
    ''
