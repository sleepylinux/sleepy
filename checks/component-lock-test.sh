#!/usr/bin/env bash
set -euo pipefail

for required_command in jq mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'component lock self-test: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/component-lock.sh"
manifest="$repo_root/components/desktop-m1.json"
fixture=$(mktemp -d /tmp/sleepy-component-lock.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

test -x "$contract"

good="$fixture/flake.lock"
jq -n --slurpfile reviewed "$manifest" '
  {
    version: 7,
    root: "root",
    nodes: (
      {
        root: {
          inputs: ($reviewed[0].inputs | with_entries(.value = .key))
        }
      } +
      ($reviewed[0].inputs | with_entries(
        .value = {
          locked: {
            type: "github",
            owner: "sleepylinux",
            repo: .key,
            rev: .value.revision,
            narHash: "sha256-contract-fixture"
          }
        }
      ))
    )
  }
' >"$good"

bash "$contract" "$manifest" "$good"

assert_rejected() {
  local name=$1
  local filter=$2
  local rejected="$fixture/rejected.lock"

  jq "$filter" "$good" >"$rejected"
  if bash "$contract" "$manifest" "$rejected" >/dev/null 2>&1; then
    printf 'component lock contract accepted invalid fixture: %s\n' \
      "$name" >&2
    return 1
  fi
}

assert_rejected missing-root-input 'del(.nodes.root.inputs["sleepy-sdk"])'
assert_rejected moving-revision \
  '.nodes["sleepy-session"].locked.rev = "0000000000000000000000000000000000000000"'
assert_rejected wrong-owner \
  '.nodes["sleepy-artwork"].locked.owner = "someone-else"'
assert_rejected missing-content-hash \
  'del(.nodes["sleepy-desktop"].locked.narHash)'

printf 'component lock self-test: ok\n'
