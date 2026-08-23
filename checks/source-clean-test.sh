#!/usr/bin/env bash
set -euo pipefail

for required_command in git rg; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'source-clean self-test: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/source-clean.sh"
fixture=$(mktemp -d /tmp/sleepy-source-clean.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

git -C "$fixture" init --quiet
git -C "$fixture" config user.email sleepy-contract@example.invalid
git -C "$fixture" config user.name "Sleepy contract test"
printf 'local/\nsecrets/\n.superpowers/\nresult\nresult-*\noutputs/\n' >"$fixture/.gitignore"
printf '{ imports = []; }\n' >"$fixture/flake.nix"
git -C "$fixture" add .gitignore flake.nix
git -C "$fixture" commit --quiet -m fixture

bash "$contract" "$fixture"

mkdir -p "$fixture/.superpowers" "$fixture/local" "$fixture/secrets"
printf 'ignored developer state\n' >"$fixture/.superpowers/progress.md"
printf 'ignored local module\n' >"$fixture/local/default.nix"
printf '%s%s\n' '-----BEGIN OPENSSH PRIVATE' ' KEY-----' >"$fixture/secrets/id_ed25519"
bash "$contract" "$fixture"

printf '%s%s\n' '-----BEGIN PRIVATE' ' KEY-----' >"$fixture/untracked-scratch.txt"
bash "$contract" "$fixture"
rm -f -- "$fixture/untracked-scratch.txt"

assert_rejected() {
  local name=$1
  local relative_path=$2
  local payload=$3
  local probe="$fixture/$relative_path"

  mkdir -p "$(dirname "$probe")"
  printf '%s\n' "$payload" >"$probe"
  git -C "$fixture" add --force "$relative_path"
  if bash "$contract" "$fixture" >/dev/null 2>&1; then
    git -C "$fixture" reset --quiet HEAD -- "$relative_path"
    rm -f -- "$probe"
    printf 'source contract accepted forbidden probe: %s\n' "$name" >&2
    return 1
  fi
  git -C "$fixture" reset --quiet HEAD -- "$relative_path"
  rm -f -- "$probe"
}

assert_symlink_rejected() {
  local name=$1
  local relative_path=$2
  local target=$3
  local probe="$fixture/$relative_path"

  mkdir -p "$(dirname "$probe")"
  ln -s -- "$target" "$probe"
  git -C "$fixture" add --force "$relative_path"
  if bash "$contract" "$fixture" >/dev/null 2>&1; then
    git -C "$fixture" reset --quiet HEAD -- "$relative_path"
    rm -f -- "$probe"
    printf 'source contract accepted forbidden symlink probe: %s\n' "$name" >&2
    return 1
  fi
  git -C "$fixture" reset --quiet HEAD -- "$relative_path"
  rm -f -- "$probe"
}

assert_nested_symlink_rejected() {
  local name=$1
  local relative_path=$2
  local intermediate_path=$3
  local intermediate_target=$4
  local probe="$fixture/$relative_path"
  local intermediate="$fixture/$intermediate_path"

  mkdir -p "$(dirname "$probe")" "$(dirname "$intermediate")"
  ln -s -- "$intermediate_target" "$intermediate"
  ln -s -- "$intermediate_path" "$probe"
  git -C "$fixture" add --force "$relative_path"
  if bash "$contract" "$fixture" >/dev/null 2>&1; then
    git -C "$fixture" reset --quiet HEAD -- "$relative_path"
    rm -f -- "$probe" "$intermediate"
    printf 'source contract accepted forbidden nested symlink probe: %s\n' "$name" >&2
    return 1
  fi
  git -C "$fixture" reset --quiet HEAD -- "$relative_path"
  rm -f -- "$probe" "$intermediate"
}

assert_rejected tracked-local local/default.nix '{ ... }: {}'
assert_rejected tracked-secret secrets/token.txt 'not-a-real-secret'
assert_rejected nix-local-dependency modules/probe.nix '{ imports = [ ../local/probe.nix ]; }'
assert_rejected nix-secret-dependency modules/probe.nix '{ imports = [ ../secrets/probe.nix ]; }'
assert_rejected generated-result result 'generated output'
assert_rejected generated-results results/build.txt 'generated output'
assert_rejected generated-output outputs/build.txt 'generated output'
private_key_marker='-----BEGIN PRIVATE'
private_key_marker+=' KEY-----'
assert_rejected private-key packages/key.pem "$private_key_marker"
openssh_key_marker='-----BEGIN OPENSSH PRIVATE'
openssh_key_marker+=' KEY-----'
assert_rejected openssh-private-key packages/key.txt "$openssh_key_marker"
assert_symlink_rejected repository-escape nested/escape-link ../../outside
assert_symlink_rejected direct-local-symlink local-link local/secret
assert_nested_symlink_rejected nested-local-symlink chain-link nested/bridge ../local/secret
pgp_key_marker='-----BEGIN PGP PRIVATE'
pgp_key_marker+=' KEY BLOCK-----'
assert_rejected pgp-private-key packages/key.asc "$pgp_key_marker"
assert_rejected artifact-upload .github/workflows/probe.yml 'uses: actions/upload-artifact@v4'

bash "$contract" "$repo_root"
printf 'source-clean contract self-test: ok\n'
