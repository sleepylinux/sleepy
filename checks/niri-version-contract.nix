{
  pkgs,
  source,
}: let
  evaluate = overrides:
    pkgs.lib.evalModules {
      modules = [
        (import ../modules/nixos/base/niri-version.nix)
        ({lib, ...}: {
          options.assertions = lib.mkOption {
            type = lib.types.listOf (lib.types.submodule {
              options = {
                assertion = lib.mkOption {type = lib.types.bool;};
                message = lib.mkOption {type = lib.types.str;};
              };
            });
            default = [];
          };
          options.programs.niri.package = lib.mkOption {type = lib.types.attrs;};
          config.programs.niri.package = lib.mkDefault {version = "26.04";};
        })
      ] ++ overrides;
    };
  accepted = evaluate [];
  rejected = evaluate [
    ({lib, ...}: {
      config.programs.niri.package = lib.mkForce {version = "26.03";};
    })
  ];
in
  assert pkgs.lib.assertMsg
  (builtins.all (entry: entry.assertion) accepted.config.assertions)
  "the minimum supported Niri version must satisfy the assertion";
  assert pkgs.lib.assertMsg
  (builtins.any (entry: !entry.assertion) rejected.config.assertions)
  "an overridden Niri 26.03 package must fail the version assertion";
    pkgs.runCommand "sleepy-niri-version-contract" {nativeBuildInputs = [pkgs.gnugrep];} ''
      grep -F 'config.programs.niri.package.version' ${source}/modules/nixos/base/niri-version.nix
      touch "$out"
    ''
