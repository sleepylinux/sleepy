#!/usr/bin/env bash
# shellcheck disable=SC2016 # Backticks below are literal user instructions.
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
  def historical_revisions($manifest; $repo):
    ([if $repo == "sleepy" then $manifest.root.revision else $manifest.inputs[$repo].revision end] +
      [($manifest.ancestors // [])[] |
        if $repo == "sleepy" then .root.revision else .inputs[$repo].revision end]) |
      map(select(type == "string"));
  def root_node_for_revision($lock; $nodes; $revision):
    [$nodes[] |
      select(
        $lock.nodes[.].locked?.type == "github" and
        $lock.nodes[.].locked?.owner == "sleepylinux" and
        $lock.nodes[.].locked?.repo == "sleepy" and
        $lock.nodes[.].locked?.rev == $revision
      )] |
    if length == 1 then .[0] else null end;
  def exact_component_edges($lock; $root; $snapshot):
    ($root | type == "string") and
    all($snapshot.inputs | to_entries[];
      . as $input |
      ($lock.nodes[$root].inputs[$input.key] | type == "string") and
      ($lock.nodes[$lock.nodes[$root].inputs[$input.key]].locked.type == "github") and
      ($lock.nodes[$lock.nodes[$root].inputs[$input.key]].locked.owner == "sleepylinux") and
      ($lock.nodes[$lock.nodes[$root].inputs[$input.key]].locked.repo == $input.key) and
      ($lock.nodes[$lock.nodes[$root].inputs[$input.key]].locked.rev == $input.value.revision) and
      valid_hash($lock.nodes[$lock.nodes[$root].inputs[$input.key]])
    );
  def exact_direct_edges($lock; $root; $snapshot; $ancestorInput; $ancestorRoot):
    exact_component_edges($lock; $root; $snapshot) and
    (if $ancestorInput == null then
      $ancestorRoot == null
    else
      ($ancestorInput | type == "string" and length > 0) and
      ($ancestorRoot | type == "string") and
      ($lock.nodes[$root].inputs[$ancestorInput] == $ancestorRoot)
    end) and
    all(($lock.nodes[$root].inputs // {}) | to_entries[];
      . as $edge |
      $lock.nodes[$edge.value].locked? as $target |
      if ($target.owner == "sleepylinux") then
        (($snapshot.inputs | has($edge.key)) or $edge.key == $ancestorInput)
      else true
      end
    );

  . as $lock |
  $reviewed[0] as $currentManifest |
  $baseline[0] as $baselineManifest |
  .nodes[.root].inputs as $rootInputs |
  [$currentManifest.inputs | keys[] | $rootInputs[.]] as $currentRoots |
  $rootInputs["sleepy-m2-baseline"] as $baselineRoot |
  closure($currentRoots) as $currentClosure |
  closure([$baselineRoot]) as $baselineClosure |
  ($baselineManifest.ancestors // []) as $ancestors |
  (if ($ancestors | length) == 0 then null else
    root_node_for_revision($lock; $baselineClosure; $ancestors[0].root.revision)
  end) as $firstAncestorRoot |

  ($baselineRoot | type == "string") and
  (.nodes[$baselineRoot].locked.type == "github") and
  (.nodes[$baselineRoot].locked.owner == "sleepylinux") and
  (.nodes[$baselineRoot].locked.repo == "sleepy") and
  (.nodes[$baselineRoot].locked.rev == $baselineManifest.root.revision) and
  valid_hash(.nodes[$baselineRoot]) and
  exact_direct_edges(
    $lock;
    $baselineRoot;
    $baselineManifest;
    (if ($ancestors | length) == 0 then null else $ancestors[0].input end);
    $firstAncestorRoot
  ) and

  all(range(0; $ancestors | length);
    . as $index |
    $ancestors[$index] as $ancestor |
    root_node_for_revision($lock; $baselineClosure; $ancestor.root.revision) as $ancestorRoot |
    (if $index == 0 then
      $baselineRoot
    else
      root_node_for_revision(
        $lock;
        $baselineClosure;
        $ancestors[$index - 1].root.revision
      )
    end) as $parentRoot |
    (if $index + 1 < ($ancestors | length) then
      root_node_for_revision($lock; $baselineClosure; $ancestors[$index + 1].root.revision)
    else null
    end) as $nextAncestorRoot |
    ($ancestorRoot | type == "string") and
    ($parentRoot | type == "string") and
    ($lock.nodes[$parentRoot].inputs[$ancestor.input] == $ancestorRoot) and
    exact_direct_edges(
      $lock;
      $ancestorRoot;
      $ancestor;
      (if $index + 1 < ($ancestors | length) then $ancestors[$index + 1].input else null end);
      $nextAncestorRoot
    )
  ) and

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
    if ($locked.type == "github" and $locked.owner == "sleepylinux") then
      ($currentClosure | index($entry.key)) as $inCurrent |
      ($baselineClosure | index($entry.key)) as $inBaseline |
      if $inCurrent != null and $inBaseline != null then
        ($locked.repo != "sleepy") and
        ($locked.rev == $currentManifest.inputs[$locked.repo].revision) and
        ((historical_revisions($baselineManifest; $locked.repo) | index($locked.rev)) != null) and
        valid_hash($entry.value)
      elif $inCurrent != null then
        ($currentManifest.inputs[$locked.repo] != null) and
        ($locked.rev == $currentManifest.inputs[$locked.repo].revision) and
        valid_hash($entry.value)
      elif $inBaseline != null then
        ((historical_revisions($baselineManifest; $locked.repo) | index($locked.rev)) != null) and
        valid_hash($entry.value)
      else false
      end
    else true
    end
  )
' "$lock" >/dev/null; then
  printf '%s\n' \
    'component lock: current or historical Sleepy graph does not match its immutable manifest.' \
    'Run `nix flake lock`, review the generated lock diff, then run:' \
    '  bash checks/component-lock.sh components/current.json components/desktop-m2-baseline.json flake.lock' >&2
  exit 1
fi

printf 'component lock: ok\n'
