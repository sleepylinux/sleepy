#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/baseline-provenance.sh"
baseline="$repo_root/components/desktop-m2-baseline.json"
m1_baseline="$repo_root/components/desktop-m1-baseline.json"
fixture=$(mktemp -d /tmp/sleepy-baseline-provenance.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

bash "$contract" "$baseline"
bash "$contract" "$m1_baseline"
jq '.ancestors[0].inputs["sleepy-sdk"].revision = "0000000000000000000000000000000000000000"' \
  "$baseline" >"$fixture/mutated.json"
if bash "$contract" "$fixture/mutated.json" >/dev/null 2>&1; then
  printf 'baseline provenance accepted a mutated manifest\n' >&2
  exit 1
fi

printf 'baseline provenance self-test: ok\n'
