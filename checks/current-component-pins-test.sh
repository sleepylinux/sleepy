#!/usr/bin/env bash
set -euo pipefail

for required_command in grep jq mktemp sed sha256sum; do
  command -v "$required_command" >/dev/null 2>&1 || {
    printf 'current component pins: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  }
done

repo_root=${SLEEPY_CURRENT_PINS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}
manifest="$repo_root/components/current.json"
baseline="$repo_root/components/desktop-m2-baseline.json"
deployment="$repo_root/docs/deployment.md"
acceptance="$repo_root/docs/acceptance/desktop-foundation.md"

jq -e '
  .schemaVersion == 1 and
  .milestone == "desktop-m3" and
  (.distributionVersion | test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.packageVersions | keys | sort) == ["sleepy-artwork", "sleepy-desktop", "sleepy-extensions", "sleepy-sdk", "sleepy-session"] and
  all(.packageVersions[]; test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and
  (.flakeLockSha256 | test("^[0-9a-f]{64}$")) and
  (.inputs | keys | sort) == ["sleepy-artwork", "sleepy-desktop", "sleepy-sdk", "sleepy-session"] and
  all(.inputs | to_entries[];
    (.value.revision | test("^[0-9a-f]{40}$")) and
    .value.url == ("github:sleepylinux/" + .key + "/" + .value.revision))
' "$manifest" >/dev/null

bash "$repo_root/checks/flake-input-contract.sh" \
  "$repo_root/flake.nix" "$manifest" "$baseline" >/dev/null
bash "$repo_root/checks/component-lock.sh" \
  "$manifest" "$baseline" "$repo_root/flake.lock" >/dev/null

approved_lock_sha=$(jq -r '.flakeLockSha256' "$manifest")
computed_lock_sha=$(sha256sum "$repo_root/flake.lock" | awk '{print $1}')
test "$approved_lock_sha" = "$computed_lock_sha" || {
  printf 'current component pins: flake.lock digest differs from current manifest\n' >&2
  exit 1
}

deployment_section=$(mktemp /tmp/sleepy-deployment-current.XXXXXX)
acceptance_section=$(mktemp /tmp/sleepy-acceptance-current.XXXXXX)
trap 'rm -f -- "$deployment_section" "$acceptance_section"' EXIT
sed -n '/<!-- BEGIN CURRENT COMPONENT GRAPH -->/,/<!-- END CURRENT COMPONENT GRAPH -->/p' \
  "$deployment" >"$deployment_section"
sed -n '/<!-- BEGIN CURRENT COMPONENT GRAPH -->/,/<!-- END CURRENT COMPONENT GRAPH -->/p' \
  "$acceptance" >"$acceptance_section"

for section in "$deployment_section" "$acceptance_section"; do
  test "$(grep -Eoc '[0-9a-f]{64}' "$section")" -eq 1
  grep -Fq "$approved_lock_sha" "$section"
done

component_count=$(jq '.inputs | length' "$manifest")
test "$(grep -Ec '^sleepy-[a-z0-9-]+[[:space:]]+[0-9a-f]{40}$' "$deployment_section")" \
  -eq "$component_count"
test "$(grep -Ec '^\| `sleepy-[a-z0-9-]+` \| `[0-9a-f]{40}` \|$' "$acceptance_section")" \
  -eq "$component_count"

while IFS=$'\t' read -r component revision; do
  grep -Eq "^${component}[[:space:]]+${revision}$" "$deployment_section"
  grep -Fqx "| \`$component\` | \`$revision\` |" "$acceptance_section"
done < <(jq -r '.inputs | to_entries[] | [.key, .value.revision] | @tsv' "$manifest")

printf 'current component pins: ok\n'
