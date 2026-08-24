#!/usr/bin/env bash
set -euo pipefail

for required_command in awk grep jq mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'current component pins: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
manifest="$repo_root/components/desktop-m1.json"
baseline="$repo_root/components/desktop-m1-baseline.json"
expected=$(mktemp /tmp/sleepy-current-component-pins.XXXXXX.json)
deployment_candidate=$(mktemp /tmp/sleepy-deployment-candidate.XXXXXX.md)
acceptance_candidate=$(mktemp /tmp/sleepy-acceptance-candidate.XXXXXX.md)
trap 'rm -f -- "$expected" "$deployment_candidate" "$acceptance_candidate"' EXIT

cat >"$expected" <<'EOF'
{
  "schemaVersion": 1,
  "milestone": "desktop-m2",
  "inputs": {
    "sleepy-sdk": {
      "url": "github:sleepylinux/sleepy-sdk/5dc792faea9d743fabbb576ae1b25ed7e1f729f9",
      "revision": "5dc792faea9d743fabbb576ae1b25ed7e1f729f9"
    },
    "sleepy-session": {
      "url": "github:sleepylinux/sleepy-session/b88f5b993ae449acf176d8fc6f0d6542776d06bd",
      "revision": "b88f5b993ae449acf176d8fc6f0d6542776d06bd"
    },
    "sleepy-artwork": {
      "url": "github:sleepylinux/sleepy-artwork/108487617077254edb4e3a3b21047f5621eef151",
      "revision": "108487617077254edb4e3a3b21047f5621eef151"
    },
    "sleepy-desktop": {
      "url": "github:sleepylinux/sleepy-desktop/0b612df154e0606ced56020a56a54fa1f42dd3db",
      "revision": "0b612df154e0606ced56020a56a54fa1f42dd3db"
    }
  }
}
EOF

failures=0

if ! jq -e --slurpfile expected "$expected" \
  '.milestone == "desktop-m2" and .inputs == $expected[0].inputs' \
  "$manifest" >/dev/null; then
  printf 'current component pins: current manifest does not match the approved M2 revisions\n' >&2
  failures=1
fi

if ! bash "$repo_root/checks/flake-input-contract.sh" \
  "$repo_root/flake.nix" "$expected" "$baseline" >/dev/null 2>&1; then
  printf 'current component pins: flake input literals do not match the approved M2 revisions\n' >&2
  failures=1
fi

if ! bash "$repo_root/checks/component-lock.sh" \
  "$expected" "$baseline" "$repo_root/flake.lock" >/dev/null 2>&1; then
  printf 'current component pins: generated lock graph does not match the approved M2 revisions\n' >&2
  failures=1
fi

awk '/^## Desktop Milestone 2 candidate gate$/ { keep=1 } /^## Deployment boundary$/ { keep=0 } keep' \
  "$repo_root/docs/deployment.md" >"$deployment_candidate"
awk '/^## Desktop Milestone 2 integration candidate$/ { keep=1 } /^## Desktop Milestone 1 VM deployment/ { keep=0 } keep' \
  "$repo_root/docs/acceptance/desktop-foundation.md" >"$acceptance_candidate"

for expected_line in \
  'sleepy-sdk      5dc792faea9d743fabbb576ae1b25ed7e1f729f9' \
  'sleepy-session  b88f5b993ae449acf176d8fc6f0d6542776d06bd' \
  'sleepy-artwork  108487617077254edb4e3a3b21047f5621eef151' \
  'sleepy-desktop  0b612df154e0606ced56020a56a54fa1f42dd3db'; do
  if ! grep -Fx -- "$expected_line" "$deployment_candidate" >/dev/null; then
    printf 'current component pins: deployment candidate table is missing %s\n' \
      "$expected_line" >&2
    failures=1
  fi
done

while IFS=$'\t' read -r component revision; do
  expected_line="| \`$component\` | \`$revision\` |"
  if ! grep -Fx -- "$expected_line" "$acceptance_candidate" >/dev/null; then
    printf 'current component pins: acceptance candidate table is missing %s\n' \
      "$expected_line" >&2
    failures=1
  fi
done <<'EOF'
sleepy-sdk	5dc792faea9d743fabbb576ae1b25ed7e1f729f9
sleepy-session	b88f5b993ae449acf176d8fc6f0d6542776d06bd
sleepy-artwork	108487617077254edb4e3a3b21047f5621eef151
sleepy-desktop	0b612df154e0606ced56020a56a54fa1f42dd3db
EOF

if test "$failures" -ne 0; then
  exit 1
fi

printf 'current component pins: ok\n'
