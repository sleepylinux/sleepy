#!/usr/bin/env bash
set -euo pipefail

for required_command in ln mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'update safety contract self-test: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/update-safety-contract.sh"
fixture=$(mktemp -d /tmp/sleepy-update-safety-contract.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

if ! test -x "$contract"; then
  printf 'update safety contract self-test: contract executable is missing\n' >&2
  exit 1
fi

positive="$fixture/positive"
mkdir -p "$positive/home-files" "$positive/sources"
: >"$positive/activate"
bash "$contract" "$positive/home-files" "$positive/activate" "$positive/sources"

assert_owned_path_rejected() {
  local name=$1
  local relative_path=$2
  local owned="$fixture/$name"

  mkdir -p "$owned/home-files/$(dirname "$relative_path")" "$owned/sources"
  : >"$owned/activate"
  : >"$owned/home-files/$relative_path"
  if bash "$contract" "$owned/home-files" "$owned/activate" "$owned/sources" >/dev/null 2>&1; then
    printf 'update safety contract accepted Home Manager-owned path: %s\n' \
      "$relative_path" >&2
    return 1
  fi
}

assert_owned_path_rejected settings-owned \
  '.config/sleepy/settings.json'
assert_owned_path_rejected presets-owned \
  '.local/state/sleepy/presets.json'
assert_owned_path_rejected generated-bindings-owned \
  '.config/niri/sleepy-user-bindings.kdl'

dangling="$fixture/dangling-presets"
mkdir -p "$dangling/home-files/.local/state/sleepy" "$dangling/sources"
: >"$dangling/activate"
ln -s /does-not-exist "$dangling/home-files/.local/state/sleepy/presets.json"
if bash "$contract" "$dangling/home-files" "$dangling/activate" "$dangling/sources" >/dev/null 2>&1; then
  printf 'update safety contract accepted a Home Manager-owned dangling presets link\n' >&2
  exit 1
fi

assert_activation_reference_rejected() {
  local name=$1
  local relative_path=$2
  local generated="$fixture/$name"

  mkdir -p "$generated/home-files" "$generated/sources"
  printf '%s\n' "$relative_path" >"$generated/activate"
  if bash "$contract" "$generated/home-files" "$generated/activate" "$generated/sources" >/dev/null 2>&1; then
    printf 'update safety contract accepted activation ownership of path: %s\n' \
      "$relative_path" >&2
    return 1
  fi
}

assert_activation_reference_rejected activation-settings \
  '.config/sleepy/settings.json'
assert_activation_reference_rejected activation-presets \
  '.local/state/sleepy/presets.json'

approved_initializer="$fixture/approved-initializer"
mkdir -p "$approved_initializer/home-files" "$approved_initializer/sources"
cat >"$approved_initializer/activate" <<'EOF'
unset NIRI_SOCKET
sleepyctl bindings reconcile
test -e "${XDG_CONFIG_HOME}/niri/sleepy-user-bindings.kdl" || sleepyctl bindings init
EOF
bash "$contract" \
  "$approved_initializer/home-files" \
  "$approved_initializer/activate" \
  "$approved_initializer/sources"

printf 'update safety contract self-test: ok\n'
