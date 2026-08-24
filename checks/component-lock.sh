#!/usr/bin/env bash
set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  printf 'component lock: required command not found: jq\n' >&2
  exit 127
fi

if test "$#" -ne 3; then
  printf 'usage: %s <reviewed-manifest.json> <baseline-manifest.json> <flake.lock>\n' \
    "${0##*/}" >&2
  exit 2
fi

manifest=$1
baseline_manifest=$2
lock=$3

if ! jq -e \
  --slurpfile reviewed "$manifest" \
  --slurpfile baseline "$baseline_manifest" '
  def children($id):
    [(.nodes[$id].inputs // {})[] | select(type == "string")];
  def closure($starts):
    def walk($todo; $seen):
      if ($todo | length) == 0 then $seen
      else $todo[0] as $node |
        if ($seen | index($node)) != null then
          walk($todo[1:]; $seen)
        else
          walk(($todo[1:] + children($node)); ($seen + [$node]))
        end
      end;
    walk($starts; []);
  def valid_hash($node):
    ($node.locked.narHash | type == "string" and startswith("sha256-") and length > 7);

  . as $lock |
  $reviewed[0] as $currentManifest |
  $baseline[0] as $baselineManifest |
  .nodes[.root].inputs as $rootInputs |
  [$currentManifest.inputs | keys[] | $rootInputs[.]] as $currentRoots |
  $rootInputs["sleepy-m1-baseline"] as $baselineRoot |
  closure($currentRoots) as $currentClosure |
  closure([$baselineRoot]) as $baselineClosure |

  ($baselineRoot | type == "string") and
  (.nodes[$baselineRoot].locked.type == "github") and
  (.nodes[$baselineRoot].locked.owner == "sleepylinux") and
  (.nodes[$baselineRoot].locked.repo == "sleepy") and
  (.nodes[$baselineRoot].locked.rev == $baselineManifest.root.revision) and
  valid_hash(.nodes[$baselineRoot]) and

  all($currentManifest.inputs | to_entries[];
    . as $input |
    ($rootInputs[$input.key] | type == "string") and
    ($lock.nodes[$rootInputs[$input.key]].locked.type == "github") and
    ($lock.nodes[$rootInputs[$input.key]].locked.owner == "sleepylinux") and
    ($lock.nodes[$rootInputs[$input.key]].locked.repo == $input.key) and
    ($lock.nodes[$rootInputs[$input.key]].locked.rev == $input.value.revision) and
    valid_hash($lock.nodes[$rootInputs[$input.key]])
  ) and

  all(.nodes | to_entries[];
    . as $entry |
    $entry.value.locked? as $locked |
    if ($locked.type == "github" and $locked.owner == "sleepylinux" and
        (($currentManifest.inputs[$locked.repo] != null) or $locked.repo == "sleepy")) then
      ($currentClosure | index($entry.key)) as $inCurrent |
      ($baselineClosure | index($entry.key)) as $inBaseline |
      if $inCurrent != null and $inBaseline != null then
        ($locked.repo != "sleepy") and
        ($currentManifest.inputs[$locked.repo].revision ==
          $baselineManifest.inputs[$locked.repo].revision) and
        ($locked.rev == $currentManifest.inputs[$locked.repo].revision) and
        valid_hash($entry.value)
      elif $inCurrent != null then
        ($currentManifest.inputs[$locked.repo] != null) and
        ($locked.rev == $currentManifest.inputs[$locked.repo].revision) and
        valid_hash($entry.value)
      elif $inBaseline != null then
        (if $locked.repo == "sleepy" then
          $locked.rev == $baselineManifest.root.revision
        else
          ($baselineManifest.inputs[$locked.repo] != null) and
          ($locked.rev == $baselineManifest.inputs[$locked.repo].revision)
        end) and valid_hash($entry.value)
      else false
      end
    else true
    end
  )
' "$lock" >/dev/null; then
  printf '%s\n' \
    'component lock: current or historical Sleepy graph does not match its immutable manifest.' \
    'Run `nix flake lock`, review the generated lock diff, then run:' \
    '  bash checks/component-lock.sh components/desktop-m1.json components/desktop-m1-baseline.json flake.lock' >&2
  exit 1
fi

printf 'component lock: ok\n'
