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
      )) +
      {
        upstream: {
          locked: {
            type: "github",
            owner: "unrelated-upstream",
            repo: "sleepy-session",
            rev: "0000000000000000000000000000000000000000",
            narHash: "sha256-unrelated-fixture"
          }
        }
      }
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
assert_rejected legacy-nested-sdk-revision \
  '.nodes["legacy-sdk"] = {locked:{type:"github",owner:"sleepylinux",repo:"sleepy-sdk",rev:"4c4f7989b957f41f3748ddfb092b0348e2ba9e88",narHash:"sha256-legacy-fixture"}}'
assert_rejected legacy-nested-artwork-revision \
  '.nodes["legacy-artwork"] = {locked:{type:"github",owner:"sleepylinux",repo:"sleepy-artwork",rev:"7785ac5dac0daa6ac1a619f1e2a9a1b1d1374da1",narHash:"sha256-legacy-fixture"}}'
assert_rejected arbitrary-nested-session-revision \
  '.nodes["nested-session"] = {locked:{type:"github",owner:"sleepylinux",repo:"sleepy-session",rev:"0000000000000000000000000000000000000000",narHash:"sha256-drift-fixture"}}'
assert_rejected nested-session-missing-content-hash \
  '.nodes["nested-session"] = {locked:{type:"github",owner:"sleepylinux",repo:"sleepy-session",rev:"1e8863839b5c4310bce251b7e10ed15926039930"}}'

printf 'component lock self-test: ok\n'
