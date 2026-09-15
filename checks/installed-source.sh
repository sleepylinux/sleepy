#!/usr/bin/env bash
# Exercise the relative input used by the real installer, including source NAR
# identity. A root-flake build alone does not exercise this input shape.
set -euo pipefail

repo_root=$(git -C "$(dirname "${BASH_SOURCE[0]}")/.." rev-parse --show-toplevel)
fixture=$(mktemp -d "${TMPDIR:-/tmp}/sleepy-installed-source.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
source=$(nix flake metadata --json --no-write-lock-file "$repo_root" | jq -r .path)
cp -a -- "$source" "$fixture/sleepy-source"
cat > "$fixture/flake.nix" <<'NIX'
{
  inputs.sleepy.url = "path:./sleepy-source";
  outputs = {sleepy, ...}: {
    packages.x86_64-linux.default = (sleepy.lib.mkSleepyHost {
      system = "x86_64-linux";
      hostName = "sleepy-source-test";
      primaryUser = "sleepy";
      hardwareModule = { ... }: {
        fileSystems."/" = { device = "/dev/disk/by-label/sleepy-root"; fsType = "btrfs"; };
        fileSystems."/boot" = { device = "/dev/disk/by-label/SLEEPY_EFI"; fsType = "vfat"; };
        nixpkgs.hostPlatform = "x86_64-linux";
        system.stateVersion = "26.05";
      };
    }).config.environment.etc."sleepy/source.json".source;
  };
}
NIX
metadata=$(nix build "path:$fixture" --no-link --print-out-paths)
normalized=$(jq -er .source_path "$metadata")
[[ "$normalized" =~ ^/nix/store/[0-9a-df-np-sv-z]{32}-source$ ]]
test -f "$normalized/flake.nix"
jq -e '.schema == 1 and .revision == null' "$metadata" > /dev/null
test "$(nix hash path "$normalized")" = "$(jq -er .nar_hash "$metadata")"
test "$(nix hash path "$source")" = "$(jq -er .nar_hash "$metadata")"
nix-store -q --references "$metadata" | grep -Fx -- "$normalized"
printf '%s\n' 'Installed relative source metadata and closure identity passed.'
