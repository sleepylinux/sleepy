#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  printf 'component lock: required command not found: jq\n' >&2
  exit 127
fi

if test "$#" -ne 2; then
  printf 'usage: %s <reviewed-manifest.json> <flake.lock>\n' \
    "${0##*/}" >&2
  exit 2
fi

manifest=$1
lock=$2

if ! jq -e --slurpfile reviewed "$manifest" '
  . as $lock |
  .nodes[.root].inputs as $rootInputs |
  (
    all($reviewed[0].inputs | to_entries[];
      . as $input |
      ($rootInputs[$input.key] | type == "string") and
      ($lock.nodes[$rootInputs[$input.key]].locked.type == "github") and
      ($lock.nodes[$rootInputs[$input.key]].locked.owner == "sleepylinux") and
      ($lock.nodes[$rootInputs[$input.key]].locked.repo == $input.key) and
      ($lock.nodes[$rootInputs[$input.key]].locked.rev == $input.value.revision) and
      ($lock.nodes[$rootInputs[$input.key]].locked.narHash |
        type == "string" and startswith("sha256-") and length > 7)
    )
  ) and
  (
    [$lock.nodes[].locked.rev?] |
    all(
      . != "4c4f7989b957f41f3748ddfb092b0348e2ba9e88" and
      . != "7785ac5dac0daa6ac1a619f1e2a9a1b1d1374da1"
    )
  )
' "$lock" >/dev/null; then
  printf '%s\n' \
    'component lock: flake.lock does not lock every reviewed root input or contains a legacy pre-GPL component revision.' \
    'Run `nix flake lock`, review the generated lock diff, then run:' \
    '  bash checks/component-lock.sh components/desktop-m1.json flake.lock' >&2
  exit 1
fi

printf 'component lock: ok\n'
