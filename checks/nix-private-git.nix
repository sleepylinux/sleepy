{
  pkgs,
  nixPackage ? import ../packages/vendor/nix-with-git {inherit pkgs;},
}: let
  nix = nixPackage;
in
  pkgs.runCommand "sleepy-nix-private-git" {
    nativeBuildInputs = [pkgs.gitMinimal];
  } ''
    set -eu
    mkdir repo
    git -C repo init -q
    printf '%s\n' 'pinned fixture' > repo/marker
    git -C repo add marker
    git -C repo -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
    revision=$(git -C repo rev-parse HEAD)
    repository="$PWD/repo"
    # Exercise a remote Git URL without external network or an SSH server.
    # The transport serves a real Git upload-pack over the requested stdio.
    cat > "$TMPDIR/git-transport" <<EOF
    #!${pkgs.runtimeShell}
    exec ${pkgs.gitMinimal}/bin/git-upload-pack "$repository"
    EOF
    chmod +x "$TMPDIR/git-transport"
    export GIT_SSH_COMMAND="$TMPDIR/git-transport" GIT_SSH_VARIANT=simple
    mkdir -p "$TMPDIR/home" "$TMPDIR/cache" "$TMPDIR/conf"
    export HOME="$TMPDIR/home" XDG_CACHE_HOME="$TMPDIR/cache"
    export NIX_CONF_DIR="$TMPDIR/conf" NIX_STATE_DIR="$TMPDIR/state"
    export NIX_LOG_DIR="$TMPDIR/log" NIX_STORE_DIR="$TMPDIR/store"
    export NIX_REMOTE=local
    export NIX_CONFIG='experimental-features = nix-command flakes'
    export PATH=/nonexistent
    ! command -v git
    test ! -e ${nix}/bin/git
    actual=$(${nix}/bin/nix eval --impure --raw --expr \
      "(builtins.fetchGit { url = \"ssh://fixture.invalid/repository\"; rev = \"$revision\"; }).rev")
    test "$actual" = "$revision"
    tree=$(${nix}/bin/nix eval --impure --raw --expr \
      "(builtins.fetchTree { type = \"git\"; url = \"ssh://fixture.invalid/repository\"; rev = \"$revision\"; }).rev")
    test "$tree" = "$revision"
    test "$(${nix}/bin/nix-instantiate --eval --expr '1 + 1')" = 2
    test "$(${nix}/bin/nix-daemon --version)" = "nix-daemon (Nix) ${nix.version}"
    test "$(${nix}/bin/nix-store --version)" = "nix-store (Nix) ${nix.version}"
    test "$(${nix}/bin/nix-build --version)" = "nix-build (Nix) ${nix.version}"
    ! command -v git
    printf '%s\n' 'Git fetchers and legacy CLI work without Git in caller PATH' > "$out"
  ''
