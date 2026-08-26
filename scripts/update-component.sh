#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 2; then
  printf 'usage: %s <sleepy-sdk|sleepy-session|sleepy-artwork|sleepy-desktop> <40-char-revision>\n' "${0##*/}" >&2
  exit 2
fi

component=$1
revision=$2
case "$component" in
  sleepy-sdk|sleepy-session|sleepy-artwork|sleepy-desktop) ;;
  *) printf 'unsupported component: %s\n' "$component" >&2; exit 2 ;;
esac
if [[ ! "$revision" =~ ^[0-9a-f]{40}$ ]]; then
  printf 'revision must be a lowercase 40-character Git SHA\n' >&2
  exit 2
fi
for command in jq nix perl sha256sum; do
  command -v "$command" >/dev/null || {
    printf 'required command is unavailable: %s\n' "$command" >&2
    exit 127
  }
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest="$repo_root/components/current.json"
backup_dir=$(mktemp -d "$repo_root/components/.update-backup.XXXXXX")
cp "$manifest" "$backup_dir/current.json"
cp "$repo_root/flake.nix" "$backup_dir/flake.nix"
cp "$repo_root/flake.lock" "$backup_dir/flake.lock"
cp "$repo_root/docs/deployment.md" "$backup_dir/deployment.md"
cp "$repo_root/docs/acceptance/desktop-foundation.md" "$backup_dir/desktop-foundation.md"
committed=0
candidate=
cleanup() {
  if test "$committed" -ne 1; then
    cp "$backup_dir/current.json" "$manifest"
    cp "$backup_dir/flake.nix" "$repo_root/flake.nix"
    cp "$backup_dir/flake.lock" "$repo_root/flake.lock"
    cp "$backup_dir/deployment.md" "$repo_root/docs/deployment.md"
    cp "$backup_dir/desktop-foundation.md" "$repo_root/docs/acceptance/desktop-foundation.md"
  fi
  if test -n "$candidate"; then
    rm -f -- "$candidate"
  fi
  rm -rf -- "$backup_dir"
}
trap cleanup EXIT
candidate=$(mktemp "$repo_root/components/.current.XXXXXX")

jq --arg component "$component" --arg revision "$revision" '
  .inputs[$component].revision = $revision |
  .inputs[$component].url = ("github:sleepylinux/" + $component + "/" + $revision)
' "$manifest" >"$candidate"
mv "$candidate" "$manifest"

SLEEPY_COMPONENT="$component" SLEEPY_REVISION="$revision" perl -0pi -e '
  $component = $ENV{"SLEEPY_COMPONENT"};
  $revision = $ENV{"SLEEPY_REVISION"};
  $count = s{(\Q$component\E\s*=\s*\{.*?url\s*=\s*"github:sleepylinux/\Q$component\E/)[0-9a-f]{40}}{$1$revision}gs;
  die "flake input literal was not updated\n" unless $count == 1;
' "$repo_root/flake.nix"

cd "$repo_root"
nix flake lock --update-input "$component"
lock_hash=$(sha256sum flake.lock | awk '{print $1}')
candidate=$(mktemp "$repo_root/components/.current.XXXXXX")
jq --arg hash "$lock_hash" '.flakeLockSha256 = $hash' "$manifest" >"$candidate"
mv "$candidate" "$manifest"
bash scripts/render-current-components.sh

bash checks/flake-input-contract.sh flake.nix components/current.json components/desktop-m2-baseline.json
bash checks/component-lock.sh components/current.json components/desktop-m2-baseline.json flake.lock
bash checks/current-component-pins-test.sh
committed=1
printf 'updated %s to %s; review flake.lock and components/current.json together\n' "$component" "$revision"
