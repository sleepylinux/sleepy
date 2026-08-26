{inputs}: final: _prev: let
  system = final.stdenv.hostPlatform.system;
  componentContract = builtins.fromJSON (builtins.readFile ../components/current.json);
  mappedPackages =
    builtins.mapAttrs (
      _packageName: mapping:
        inputs.${mapping.input}.packages.${system}.${mapping.output}
    )
    componentContract.rootPackages;
in
  mappedPackages
  // {
    sleepy-journal-fault-runner = final.callPackage ../packages/sleepy-journal-fault-runner {
      sleepy-session = mappedPackages.sleepy-session;
    };
  }
