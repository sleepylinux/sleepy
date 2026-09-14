{
  pkgs,
  package ? pkgs.nix,
}:
package.overrideAttrs (old: {
  nativeBuildInputs = (old.nativeBuildInputs or []) ++ [pkgs.makeBinaryWrapper];
  # Nix 2.34 invokes Git for Git-backed flake inputs and builtins.fetchGit.
  # Keep the tool private to Nix rather than enabling the development profile.
  # Wrap the shared CLI; legacy aliases require their original argv[0].
  installPhase =
    old.installPhase
    + ''
      wrapProgram "$out/bin/nix" \
        --prefix PATH : ${pkgs.lib.makeBinPath [pkgs.gitMinimal]} \
        --inherit-argv0
    '';
})
