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
approved_lock_sha=f8b178c286b871ebdc267d67f66decf606a603295a21e883358a75f4c248992d

cat >"$expected" <<'EOF'
{
  "schemaVersion": 1,
  "milestone": "desktop-m3",
  "inputs": {
    "sleepy-sdk": {
      "url": "github:sleepylinux/sleepy-sdk/152173b470fa7d1e90c6d3d6be103a4a4d3529bc",
      "revision": "152173b470fa7d1e90c6d3d6be103a4a4d3529bc"
    },
    "sleepy-session": {
      "url": "github:sleepylinux/sleepy-session/03eef8fa32595d7887ed36830212f9abc6c01a84",
      "revision": "03eef8fa32595d7887ed36830212f9abc6c01a84"
    },
    "sleepy-artwork": {
      "url": "github:sleepylinux/sleepy-artwork/175314b9c236c1b412e8e1ebc54bbe3937b0c90d",
      "revision": "175314b9c236c1b412e8e1ebc54bbe3937b0c90d"
    },
    "sleepy-desktop": {
      "url": "github:sleepylinux/sleepy-desktop/e52bf09a6472366d182209de9ea083a69364721c",
      "revision": "e52bf09a6472366d182209de9ea083a69364721c"
    }
  }
}
EOF

failures=0

if ! jq -e --slurpfile expected "$expected" \
  '.milestone == "desktop-m3" and .inputs == $expected[0].inputs' \
  "$manifest" >/dev/null; then
  printf 'current component pins: current manifest does not match the approved M3 revisions\n' >&2
  failures=1
fi

if ! bash "$repo_root/checks/flake-input-contract.sh" \
  "$repo_root/flake.nix" "$expected" "$baseline" >/dev/null 2>&1; then
  printf 'current component pins: flake input literals do not match the approved M3 revisions\n' >&2
  failures=1
fi

if ! bash "$repo_root/checks/component-lock.sh" \
  "$expected" "$baseline" "$repo_root/flake.lock" >/dev/null 2>&1; then
  printf 'current component pins: generated lock graph does not match the approved M3 revisions\n' >&2
  failures=1
fi

awk '/^## Desktop Milestone 3 candidate gate$/ { keep=1 } /^## Desktop Milestone 2 candidate gate$/ { keep=0 } keep' \
  "$repo_root/docs/deployment.md" >"$deployment_candidate"
awk '/^## Desktop Milestone 3 integration candidate$/ { keep=1 } /^## Desktop Milestone 2 integration candidate$/ { keep=0 } keep' \
  "$repo_root/docs/acceptance/desktop-foundation.md" >"$acceptance_candidate"

computed_lock_sha=$(sha256sum "$repo_root/flake.lock" | awk '{print $1}')
if test "$computed_lock_sha" != "$approved_lock_sha"; then
  printf 'current component pins: generated lock SHA-256 does not match the approved M2 lock\n' >&2
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
    printf 'current component pins: %s candidate must contain exactly the approved generated lock SHA-256\n' \
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
  'sleepy-sdk      152173b470fa7d1e90c6d3d6be103a4a4d3529bc' \
  'sleepy-session  03eef8fa32595d7887ed36830212f9abc6c01a84' \
  'sleepy-artwork  175314b9c236c1b412e8e1ebc54bbe3937b0c90d' \
  'sleepy-desktop  e52bf09a6472366d182209de9ea083a69364721c'; do
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
sleepy-sdk	152173b470fa7d1e90c6d3d6be103a4a4d3529bc
sleepy-session	03eef8fa32595d7887ed36830212f9abc6c01a84
sleepy-artwork	175314b9c236c1b412e8e1ebc54bbe3937b0c90d
sleepy-desktop	e52bf09a6472366d182209de9ea083a69364721c
EOF

if test "$failures" -ne 0; then
  exit 1
fi

if test "${SLEEPY_CURRENT_PINS_FIXTURE:-0}" != 1; then
  fixture=$(mktemp -d /tmp/sleepy-current-component-pins-fixture.XXXXXX)
  trap 'rm -rf -- "$fixture"; rm -f -- "$expected" "$deployment_candidate" "$acceptance_candidate"' EXIT
  mkdir -p "$fixture/checks" "$fixture/components" "$fixture/docs/acceptance"
  cp "$repo_root/flake.nix" "$repo_root/flake.lock" "$fixture/"
  cp "$repo_root/components/desktop-m1.json" \
    "$repo_root/components/desktop-m2-baseline.json" "$fixture/components/"
  cp "$repo_root/checks/flake-input-contract.sh" \
    "$repo_root/checks/component-lock.sh" "$fixture/checks/"
  cp "$repo_root/docs/deployment.md" "$fixture/docs/"
  cp "$repo_root/docs/acceptance/desktop-foundation.md" "$fixture/docs/acceptance/"
  chmod u+w "$fixture/docs/deployment.md" \
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

  sed -i '0,/f8b178c286b871ebdc267d67f66decf606a603295a21e883358a75f4c248992d/s//0000000000000000000000000000000000000000000000000000000000000000/' \
    "$fixture/docs/deployment.md"
  assert_rejected deployment-lock-sha
  cp "$repo_root/docs/deployment.md" "$fixture/docs/deployment.md"

  sed -i '0,/f8b178c286b871ebdc267d67f66decf606a603295a21e883358a75f4c248992d/s//0000000000000000000000000000000000000000000000000000000000000000/' \
    "$fixture/docs/acceptance/desktop-foundation.md"
  assert_rejected acceptance-lock-sha
  cp "$repo_root/docs/acceptance/desktop-foundation.md" \
    "$fixture/docs/acceptance/desktop-foundation.md"

  sed -i '/^sleepy-session  03eef8fa32595d7887ed36830212f9abc6c01a84$/a sleepy-session  6f1857bd786323ad89ac91c250a8485f944eb39c' \
    "$fixture/docs/deployment.md"
  assert_rejected deployment-stale-duplicate
  cp "$repo_root/docs/deployment.md" "$fixture/docs/deployment.md"

  sed -i '/^| `sleepy-session` | `03eef8fa32595d7887ed36830212f9abc6c01a84` |$/a | `sleepy-session` | `6f1857bd786323ad89ac91c250a8485f944eb39c` |' \
    "$fixture/docs/acceptance/desktop-foundation.md"
  assert_rejected acceptance-stale-duplicate

  if test "$negative_failures" -ne 0; then
    exit 1
  fi
fi

printf 'current component pins: ok\n'
