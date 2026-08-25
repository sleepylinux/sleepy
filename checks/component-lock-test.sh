#!/usr/bin/env bash
set -euo pipefail

for required_command in jq mktemp; do
  command -v "$required_command" >/dev/null 2>&1 || exit 127
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/component-lock.sh"
manifest="$repo_root/components/desktop-m1.json"
baseline="$repo_root/components/desktop-m2-baseline.json"
fixture=$(mktemp -d /tmp/sleepy-component-lock.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

good="$fixture/flake.lock"
jq -n --slurpfile current "$manifest" --slurpfile old "$baseline" '
  {
    version: 7,
    root: "root",
    nodes: ({
      root: {inputs: (($current[0].inputs | with_entries(.value = ("current-" + .key))) + {"sleepy-m2-baseline":"baseline-root"})},
      "baseline-root": {inputs: (($old[0].inputs | with_entries(.value = ("baseline-" + .key))) + {($old[0].ancestors[0].input):"ancestor-root"}), locked:{type:"github",owner:"sleepylinux",repo:"sleepy",rev:$old[0].root.revision,narHash:"sha256-baseline-root"}},
      "ancestor-root": {inputs: ($old[0].ancestors[0].inputs | with_entries(.value = ("ancestor-" + .key))), locked:{type:"github",owner:"sleepylinux",repo:"sleepy",rev:$old[0].ancestors[0].root.revision,narHash:"sha256-ancestor-root"}},
      upstream: {locked:{type:"github",owner:"unrelated-upstream",repo:"sleepy-session",rev:"0000000000000000000000000000000000000000",narHash:"sha256-unrelated"}}
    } +
    ($current[0].inputs | with_entries(.key = ("current-" + .key) | .value = {locked:{type:"github",owner:"sleepylinux",repo:(.key | sub("^current-";"")),rev:.value.revision,narHash:"sha256-current"}})) +
    ($old[0].inputs | with_entries(.key = ("baseline-" + .key) | .value = {locked:{type:"github",owner:"sleepylinux",repo:(.key | sub("^baseline-";"")),rev:.value.revision,narHash:"sha256-baseline"}})) +
    ($old[0].ancestors[0].inputs | with_entries(.key = ("ancestor-" + .key) | .value = {locked:{type:"github",owner:"sleepylinux",repo:(.key | sub("^ancestor-";"")),rev:.value.revision,narHash:"sha256-ancestor"}})))
  }
' >"$good"

bash "$contract" "$manifest" "$baseline" "$good"

assert_rejected() {
  local name=$1
  local filter=$2
  local rejected="$fixture/$name.lock"
  jq "$filter" "$good" >"$rejected"
  if bash "$contract" "$manifest" "$baseline" "$rejected" >/dev/null 2>&1; then
    printf 'component lock accepted invalid fixture: %s\n' "$name" >&2
    return 1
  fi
}

assert_rejected moving-current '.nodes["current-sleepy-session"].locked.rev = "0000000000000000000000000000000000000000"'
assert_rejected arbitrary-historical '.nodes["baseline-sleepy-session"].locked.rev = "0000000000000000000000000000000000000000"'
assert_rejected arbitrary-ancestor '.nodes["ancestor-sleepy-session"].locked.rev = "0000000000000000000000000000000000000000"'
assert_rejected swapped-historical-edges \
  '.nodes["baseline-root"].inputs["sleepy-session"] = "ancestor-sleepy-session" | .nodes["ancestor-root"].inputs["sleepy-session"] = "baseline-sleepy-session"'
assert_rejected misnamed-ancestor-edge \
  '.nodes["baseline-root"].inputs.foo = .nodes["baseline-root"].inputs["sleepy-m1-baseline"] | del(.nodes["baseline-root"].inputs["sleepy-m1-baseline"])'
assert_rejected shadow-historical-component-edge \
  '.nodes["baseline-root"].inputs.foo = "ancestor-sleepy-session"'
assert_rejected wrong-baseline-root '.nodes["baseline-root"].locked.rev = "0000000000000000000000000000000000000000"'
assert_rejected leaked-exemption '.nodes.leaked = .nodes["baseline-sleepy-sdk"]'
assert_rejected incompatible-shared '.nodes.root.inputs["sleepy-sdk"] = "baseline-sleepy-sdk"'
assert_rejected missing-hash 'del(.nodes["baseline-sleepy-desktop"].locked.narHash)'
assert_rejected unknown-current-sleepy-repository \
  '.nodes["current-sleepy-desktop"].inputs.agent = "sleepy-agent" | .nodes["sleepy-agent"] = {locked:{type:"github",owner:"sleepylinux",repo:"sleepy-agent",rev:"0000000000000000000000000000000000000000",narHash:"sha256-agent"}}'

printf 'component lock self-test: ok\n'
