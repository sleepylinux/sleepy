#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

assert_contains() {
  local path=$1 pattern=$2
  grep -Fq -- "$pattern" "$repo_root/$path" || {
    printf 'missing journal runner contract in %s: %s\n' "$path" "$pattern" >&2
    return 1
  }
}

test -f "$repo_root/packages/sleepy-journal-fault-runner/default.nix"
test -f "$repo_root/packages/sleepy-journal-fault-runner/runner.sh"

assert_contains flake.nix 'sleepy-journal-fault-runner'
assert_contains checks/default.nix 'journal-fault-runner'
assert_contains packages/sleepy-journal-fault-runner/default.nix 'lib.licenses.gpl3Only'
assert_contains packages/sleepy-journal-fault-runner/runner.sh 'SLEEPY_FAULT_FIXTURE_MANIFEST'
assert_contains packages/sleepy-journal-fault-runner/runner.sh 'bindings reconcile'
assert_contains packages/sleepy-journal-fault-runner/runner.sh 'env -i'

printf 'journal fault runner source contract: ok\n'
