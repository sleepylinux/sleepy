# Nix runtime Git dependency

Nix 2.34 invokes Git when fetching Git-backed flake inputs and `builtins.fetchGit`
dependencies. Sleepy uses both (Quickshell and Cargo's pinned SDK source), so
system updates must work even when the optional development profile is off.

This overrides only the upstream Nix package's install phase to wrap its shared
CLI with a private Git PATH. It preserves Nix's outputs, passthru attributes and
upstream checks. Legacy CLI aliases and the daemon keep their original argv[0].
There is no `git` executable in the resulting package's `bin` directory, and Git
is not added to the user's environment. NixOS's normal `nix.package` option also
passes the package to nixos-rebuild and the daemon.

`checks.nix-private-git` uses real Git upload-pack through a hermetic SSH transport
with an empty caller PATH and fresh caches/store. It verifies `fetchGit`,
`fetchTree`, legacy evaluation and daemon/store/build aliases. The same test
fails against unwrapped Nix 2.34 with “executing git: No such file or directory”.
