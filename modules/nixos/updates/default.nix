{
  config,
  lib,
  ...
}: let
  inherit (lib) mkOption types;
  candidates = config.sleepy.updates.candidates;
in {
  options.sleepy.updates.candidates = mkOption {
    default = {};
    description = ''
      Explicitly approved immutable sleepylinux/sleepy revisions offered by
      sleepy-system. Empty by default. Adding an entry grants permission to
      build that revision; its hash verifies identity, not maintainer approval.
      This is a local catalog, not an automatically promoted release channel.
    '';
    type = types.attrsOf (types.submodule {
      options = {
        version = mkOption {
          type = types.strMatching "[A-Za-z0-9][A-Za-z0-9 ._+-]{0,79}";
          description = "Human-readable candidate version.";
        };
        revision = mkOption {
          type = types.strMatching "[0-9a-f]{40}";
          description = "Exact commit in sleepylinux/sleepy.";
        };
        nar_hash = mkOption {
          type = types.strMatching "sha256-[A-Za-z0-9+/]{43}=";
          description = "Nix source NAR hash for the exact revision.";
        };
      };
    });
  };
  config = {
    assertions =
      lib.mapAttrsToList (id: _: {
        assertion = builtins.match "[a-z0-9][a-z0-9._-]{0,63}" id != null;
        message = "Sleepy candidate IDs must be 1–64 lowercase letters, digits, dots, underscores or hyphens.";
      })
      candidates;
    environment.etc = lib.mapAttrs' (id: candidate:
      lib.nameValuePair "sleepy/candidates/${id}.json" {
        text = builtins.toJSON (candidate
          // {
            schema = 1;
            inherit id;
          });
      })
    candidates;
  };
}
