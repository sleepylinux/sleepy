#!/usr/bin/env bash
# shellcheck disable=SC2016 # Backticks below match literal Markdown code spans.
set -euo pipefail

for required_command in awk grep jq mktemp sha256sum; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'current component pins: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

repo_root=${SLEEPY_CURRENT_PINS_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
manifest="$repo_root/components/desktop-m1.json"
baseline="$repo_root/components/desktop-m2-baseline.json"
expected=$(mktemp /tmp/sleepy-current-component-pins.XXXXXX.json)
deployment_candidate=$(mktemp /tmp/sleepy-deployment-candidate.XXXXXX.md)
acceptance_candidate=$(mktemp /tmp/sleepy-acceptance-candidate.XXXXXX.md)
trap 'rm -f -- "$expected" "$deployment_candidate" "$acceptance_candidate"' EXIT
approved_lock_sha=c05b7fb17d05badf9b698ecca313b3d5104cc4e5b0e6ce8d09019561a98ba042

cat >"$expected" <<'EOF'
{
  "schemaVersion": 1,
  "milestone": "hyprland-sleepy-desktop",
  "inputs": {
    "sleepy-sdk": {
      "url": "github:sleepylinux/sleepy-sdk/d935d3d83ef3c01627cd315230607c4b04554d42",
      "revision": "d935d3d83ef3c01627cd315230607c4b04554d42"
    },
    "sleepy-session": {
      "url": "github:sleepylinux/sleepy-session/dc30d54159c19ccd5f218ba3bb29e537136790d3",
      "revision": "dc30d54159c19ccd5f218ba3bb29e537136790d3"
    },
    "sleepy-artwork": {
      "url": "github:sleepylinux/sleepy-artwork/175314b9c236c1b412e8e1ebc54bbe3937b0c90d",
      "revision": "175314b9c236c1b412e8e1ebc54bbe3937b0c90d"
    },
    "sleepy-desktop": {
      "url": "github:sleepylinux/sleepy-desktop/8cc8cd6ad9dbad8b8dc856740f981f7101b9a7b1",
      "revision": "8cc8cd6ad9dbad8b8dc856740f981f7101b9a7b1"
    }
  }
}
EOF

failures=0

if ! jq -e --slurpfile expected "$expected" \
  '.milestone == "hyprland-sleepy-desktop" and .inputs == $expected[0].inputs' \
  "$manifest" >/dev/null; then
  printf 'current component pins: current manifest does not match the reviewed Hyprland revisions\n' >&2
  failures=1
fi

if ! bash "$repo_root/checks/flake-input-contract.sh" \
  "$repo_root/flake.nix" "$expected" "$baseline" >/dev/null 2>&1; then
  printf 'current component pins: flake input literals do not match the reviewed Hyprland revisions\n' >&2
  failures=1
fi

if ! bash "$repo_root/checks/component-lock.sh" \
  "$expected" "$baseline" "$repo_root/flake.lock" >/dev/null 2>&1; then
  printf 'current component pins: generated lock graph does not match the reviewed Hyprland revisions\n' >&2
  failures=1
fi

awk '/^## Hyprland Sleepy desktop candidate gate$/ { keep=1 } /^## Desktop Milestone 3 candidate gate$/ { keep=0 } keep' \
  "$repo_root/docs/deployment.md" >"$deployment_candidate"
awk '/^## Hyprland Sleepy desktop integration candidate$/ { keep=1 } /^## Desktop Milestone 3 integration candidate$/ { keep=0 } keep' \
  "$repo_root/docs/acceptance/desktop-foundation.md" >"$acceptance_candidate"

computed_lock_sha=$(sha256sum "$repo_root/flake.lock" | awk '{print $1}')
if test "$computed_lock_sha" != "$approved_lock_sha"; then
  printf 'current component pins: generated lock SHA-256 does not match the reviewed Hyprland lock\n' >&2
  failures=1
fi

validate_candidate_lock_sha() {
  local name=$1
  local candidate=$2
  local hashes=()
  mapfile -t hashes < <(grep -Eo '`[0-9a-f]{64}`' "$candidate" | tr -d '`' || true)
  if test "${#hashes[@]}" -ne 1 || \
    test "${hashes[0]:-}" != "$approved_lock_sha" || \
    test "${hashes[0]:-}" != "$computed_lock_sha"; then
    printf 'current component pins: %s candidate must contain exactly the reviewed generated lock SHA-256\n' \
      "$name" >&2
    failures=1
  fi
}

validate_candidate_lock_sha deployment "$deployment_candidate"
validate_candidate_lock_sha acceptance "$acceptance_candidate"

mapfile -t deployment_rows < <(
  grep -E '^sleepy-[a-z0-9-]+[[:space:]]+[0-9a-f]{40}$' \
    "$deployment_candidate" || true
)
if test "${#deployment_rows[@]}" -ne 4; then
  printf 'current component pins: deployment candidate must contain exactly four component pin rows\n' >&2
  failures=1
fi

for expected_line in \
  'sleepy-sdk      d935d3d83ef3c01627cd315230607c4b04554d42' \
  'sleepy-session  dc30d54159c19ccd5f218ba3bb29e537136790d3' \
  'sleepy-artwork  175314b9c236c1b412e8e1ebc54bbe3937b0c90d' \
  'sleepy-desktop  8cc8cd6ad9dbad8b8dc856740f981f7101b9a7b1'; do
  if test "$(grep -Fxc -- "$expected_line" "$deployment_candidate")" -ne 1; then
    printf 'current component pins: deployment candidate must contain exactly one %s\n' \
      "$expected_line" >&2
    failures=1
  fi
done

mapfile -t acceptance_rows < <(
  grep -E '^\| `sleepy-[a-z0-9-]+` \| `[0-9a-f]{40}` \|$' \
    "$acceptance_candidate" || true
)
if test "${#acceptance_rows[@]}" -ne 4; then
  printf 'current component pins: acceptance candidate must contain exactly four component pin rows\n' >&2
  failures=1
fi

while IFS=$'\t' read -r component revision; do
  expected_line="| \`$component\` | \`$revision\` |"
  if test "$(grep -Fxc -- "$expected_line" "$acceptance_candidate")" -ne 1; then
    printf 'current component pins: acceptance candidate must contain exactly one %s\n' \
      "$expected_line" >&2
    failures=1
  fi
done <<'EOF'
sleepy-sdk	d935d3d83ef3c01627cd315230607c4b04554d42
sleepy-session	dc30d54159c19ccd5f218ba3bb29e537136790d3
sleepy-artwork	175314b9c236c1b412e8e1ebc54bbe3937b0c90d
sleepy-desktop	8cc8cd6ad9dbad8b8dc856740f981f7101b9a7b1
EOF

if test "$failures" -ne 0; then
  exit 1
fi

if test "${SLEEPY_CURRENT_PINS_FIXTURE:-0}" != 1; then
  fixture=$(mktemp -d /tmp/sleepy-current-component-pins-fixture.XXXXXX)
  trap 'rm -rf -- "$fixture"; rm -f -- "$expected" "$deployment_candidate" "$acceptance_candidate"' EXIT
  mkdir -p "$fixture/checks" "$fixture/components" "$fixture/docs/acceptance"
  install -m 0600 "$repo_root/flake.nix" "$fixture/flake.nix"
  install -m 0600 "$repo_root/flake.lock" "$fixture/flake.lock"
  install -m 0600 "$repo_root/components/desktop-m1.json" \
    "$fixture/components/desktop-m1.json"
  install -m 0600 "$repo_root/components/desktop-m2-baseline.json" \
    "$fixture/components/desktop-m2-baseline.json"
  cp "$repo_root/checks/flake-input-contract.sh" \
    "$repo_root/checks/component-lock.sh" "$fixture/checks/"
  install -m 0600 "$repo_root/docs/deployment.md" \
    "$fixture/docs/deployment.md"
  install -m 0600 "$repo_root/docs/acceptance/desktop-foundation.md" \
    "$fixture/docs/acceptance/desktop-foundation.md"

  negative_failures=0
  assert_rejected() {
    local name=$1
    if SLEEPY_CURRENT_PINS_ROOT="$fixture" SLEEPY_CURRENT_PINS_FIXTURE=1 \
      bash "$repo_root/checks/current-component-pins-test.sh" >/dev/null 2>&1; then
      printf 'current component pins: accepted invalid candidate fixture: %s\n' \
        "$name" >&2
      negative_failures=1
    fi
  }

  sed -i '0,/c05b7fb17d05badf9b698ecca313b3d5104cc4e5b0e6ce8d09019561a98ba042/s//0000000000000000000000000000000000000000000000000000000000000000/' \
    "$fixture/docs/deployment.md"
  assert_rejected deployment-lock-sha
  install -m 0600 "$repo_root/docs/deployment.md" "$fixture/docs/deployment.md"

  sed -i '0,/c05b7fb17d05badf9b698ecca313b3d5104cc4e5b0e6ce8d09019561a98ba042/s//0000000000000000000000000000000000000000000000000000000000000000/' \
    "$fixture/docs/acceptance/desktop-foundation.md"
  assert_rejected acceptance-lock-sha
  install -m 0600 "$repo_root/docs/acceptance/desktop-foundation.md" \
    "$fixture/docs/acceptance/desktop-foundation.md"

  sed -i '/^sleepy-session  dc30d54159c19ccd5f218ba3bb29e537136790d3$/a sleepy-session  6f1857bd786323ad89ac91c250a8485f944eb39c' \
    "$fixture/docs/deployment.md"
  assert_rejected deployment-stale-duplicate
  install -m 0600 "$repo_root/docs/deployment.md" "$fixture/docs/deployment.md"

  sed -i '/^| `sleepy-session` | `dc30d54159c19ccd5f218ba3bb29e537136790d3` |$/a | `sleepy-session` | `6f1857bd786323ad89ac91c250a8485f944eb39c` |' \
    "$fixture/docs/acceptance/desktop-foundation.md"
  assert_rejected acceptance-stale-duplicate
  install -m 0600 "$repo_root/docs/acceptance/desktop-foundation.md" \
    "$fixture/docs/acceptance/desktop-foundation.md"

  sed -i '0,/d935d3d83ef3c01627cd315230607c4b04554d42/s//0000000000000000000000000000000000000000/' \
    "$fixture/flake.nix"
  assert_rejected flake-sdk-pin
  install -m 0600 "$repo_root/flake.nix" "$fixture/flake.nix"

  sed -i '0,/dc30d54159c19ccd5f218ba3bb29e537136790d3/s//0000000000000000000000000000000000000000/' \
    "$fixture/components/desktop-m1.json"
  assert_rejected manifest-session-pin
  install -m 0600 "$repo_root/components/desktop-m1.json" \
    "$fixture/components/desktop-m1.json"

  jq '(.nodes[.nodes[.root].inputs["sleepy-desktop"]].locked.rev) =
    "0000000000000000000000000000000000000000"' \
    "$fixture/flake.lock" >"$fixture/flake.lock.mutated"
  mv "$fixture/flake.lock.mutated" "$fixture/flake.lock"
  assert_rejected lock-desktop-pin

  if test "$negative_failures" -ne 0; then
    exit 1
  fi
fi

printf 'current component pins: ok\n'
