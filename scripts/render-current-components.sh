#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
manifest="$repo_root/components/current.json"
deployment="$repo_root/docs/deployment.md"
acceptance="$repo_root/docs/acceptance/desktop-foundation.md"

for command in jq perl; do
  command -v "$command" >/dev/null || {
    printf 'required command is unavailable: %s\n' "$command" >&2
    exit 127
  }
done

lock_hash=$(jq -er '.flakeLockSha256 | select(test("^[0-9a-f]{64}$"))' "$manifest")
deployment_rows=
acceptance_rows=
for component in sleepy-sdk sleepy-session sleepy-artwork sleepy-desktop; do
  revision=$(jq -er --arg component "$component" \
    '.inputs[$component].revision | select(test("^[0-9a-f]{40}$"))' "$manifest")
  printf -v deployment_rows '%s%-16s%s\n' "$deployment_rows" "$component" "$revision"
  printf -v acceptance_rows "%s| \`%s\` | \`%s\` |\n" \
    "$acceptance_rows" "$component" "$revision"
done

deployment_block="<!-- BEGIN CURRENT COMPONENT GRAPH -->
\`\`\`text
${deployment_rows}\`\`\`

The generated candidate lock SHA-256 is
\`${lock_hash}\`.
<!-- END CURRENT COMPONENT GRAPH -->"
acceptance_block="<!-- BEGIN CURRENT COMPONENT GRAPH -->
| Component | Reviewed revision |
|---|---|
${acceptance_rows}
The generated \`flake.lock\` SHA-256 is
\`${lock_hash}\`.
<!-- END CURRENT COMPONENT GRAPH -->"

SLEEPY_GENERATED_BLOCK="$deployment_block" perl -0pi -e '
  $block = $ENV{"SLEEPY_GENERATED_BLOCK"};
  $count = s{<!-- BEGIN CURRENT COMPONENT GRAPH -->.*?<!-- END CURRENT COMPONENT GRAPH -->}{$block}s;
  die "deployment generated section is missing or duplicated\n" unless $count == 1;
' "$deployment"
SLEEPY_GENERATED_BLOCK="$acceptance_block" perl -0pi -e '
  $block = $ENV{"SLEEPY_GENERATED_BLOCK"};
  $count = s{<!-- BEGIN CURRENT COMPONENT GRAPH -->.*?<!-- END CURRENT COMPONENT GRAPH -->}{$block}s;
  die "acceptance generated section is missing or duplicated\n" unless $count == 1;
' "$acceptance"
