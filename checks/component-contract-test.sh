#!/usr/bin/env bash
set -euo pipefail

for required_command in cmp jq mktemp sha256sum; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'component contract self-test: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
contract="$repo_root/checks/component-contract.sh"
manifest="$repo_root/components/desktop-m1.json"
fixture=$(mktemp -d /tmp/sleepy-component-contract.XXXXXX)
trap 'rm -rf -- "$fixture"' EXIT

test -f "$manifest"
test -x "$contract"
fixture_bash=$(command -v bash)
test -x "$fixture_bash"

sdk="$fixture/packages/sleepy-sdk"
session="$fixture/packages/sleepy-session"
unit="$fixture/packages/sleepy-session-user-unit"
artwork="$fixture/packages/sleepy-artwork"
desktop="$fixture/packages/sleepy-desktop"
preview="$fixture/packages/sleepy-settings-preview"
sources="$fixture/sources"
validators="$fixture/validators"

mkdir -p \
  "$sdk/bin" \
  "$session/bin" \
  "$unit/share/systemd/user" \
  "$artwork/share/sleepy-artwork/branding" \
  "$desktop/bin" \
  "$desktop/share/sleepy-desktop/contracts" \
  "$preview/bin" \
  "$sources/sleepy-sdk/schemas" \
  "$sources/sleepy-sdk/fixtures/v1/settings" \
  "$sources/sleepy-sdk/fixtures/v1/preset" \
  "$sources/sleepy-sdk/fixtures/v1/plugin"
mkdir -p "$validators"

printf '#!%s\n' "$fixture_bash" >"$validators/niri"
cat >>"$validators/niri" <<'EOF'
set -euo pipefail
if test "${1:-}" = --version; then
  printf 'niri 26.04\n'
elif test "${1:-}" = validate && test "${2:-}" = --config; then
  test -f "${3:?}"
  test -f "$(dirname "$3")/bindings-core.kdl"
else
  exit 2
fi
EOF
chmod +x "$validators/niri"

printf '#!%s\n' "$fixture_bash" >"$sdk/bin/sleepy-contract"
cat >>"$sdk/bin/sleepy-contract" <<'EOF'
set -euo pipefail
test "$#" -eq 3
test "$1" = validate
kind=$2
document=$3

case "$kind" in
  settings)
    jq -e '
      .schemaVersion == 1 and
      (.activePresetId | type == "string") and
      (.appearanceMode | type == "string")
    ' "$document" >/dev/null
    ;;
  preset)
    jq -e '.schemaVersion == 1 and (.id | type == "string")' \
      "$document" >/dev/null
    ;;
  plugin)
    jq -e '
      .schemaVersion == 1 and .apiVersion == 1 and
      (.entrypoint | endswith(".qml"))
    ' "$document" >/dev/null
    ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$sdk/bin/sleepy-contract"

printf '#!%s\n' "$fixture_bash" >"$session/bin/sleepyctl"
cat >>"$session/bin/sleepyctl" <<'EOF'
set -euo pipefail

config_root=${XDG_CONFIG_HOME:-${HOME:?}/.config}
state_root=${XDG_STATE_HOME:-${HOME:?}/.local/state}
settings="$config_root/sleepy/settings.json"
presets="$state_root/sleepy/presets.json"
mkdir -p "$(dirname "$settings")" "$(dirname "$presets")"

if test ! -e "$settings"; then
  printf '%s\n' '{"schemaVersion":1,"activePresetId":"builtin.sleepy","appearanceMode":"dark","paletteSource":"sleepy","reducedMotion":false,"effectsProfile":"full","panelVisibility":"always","webSearchEnabled":true}' >"$settings"
fi
if test ! -e "$presets"; then
  printf '%s\n' '{"presets":[{"schemaVersion":1,"id":"builtin.sleepy","name":"Sleepy","origin":"builtin","basePresetId":null,"layouts":{},"drawers":[],"keybindings":[],"pluginRequirements":[]}]}' >"$presets"
fi

case "${1:-}:${2:-}:${4:-}" in
  'settings:show:')
    cat "$settings"
    ;;
  'presets:list:')
    cat "$presets"
    ;;
  presets:duplicate:*)
    printf '%s\n' '{"preset":{"id":"11111111-1111-4111-8111-111111111111","name":"Contract copy"}}'
    ;;
  presets:rename:*)
    if test "${3:-}" = builtin.sleepy; then
      printf '%s\n' '{"error":{"code":"immutable_preset","message":"built-in presets are immutable"}}' >&2
      exit 1
    fi
    jq -n --arg id "${3:?}" --arg name "${4:?}" \
      '{preset:{id:$id,name:$name}}'
    ;;
  'presets:activate:')
    printf '%s\n' '{"error":{"code":"apply_required","message":"journaled apply is required"}}' >&2
    exit 1
    ;;
  'presets:activate:--apply')
    test ! -e "$config_root/niri/sleepy-user-bindings.kdl"
    test ! -e "$state_root/sleepy/bindings-transaction.json"
    "${SLEEPY_NIRI_VALIDATOR:?}" validate --config "$config_root/niri/config.kdl"
    candidate="$settings.tmp"
    jq --arg id "${3:?}" '.activePresetId = $id' "$settings" >"$candidate"
    mv "$candidate" "$settings"
    printf '%s\n' 'binds { Mod+C { spawn "quickshell"; } }' \
      >"$config_root/niri/sleepy-user-bindings.kdl"
    printf '%s\n' '{"phase":"reloadPending"}' \
      >"$state_root/sleepy/bindings-transaction.json"
    jq -n --arg id "${3:?}" '{status:"reloadPending",activePresetId:$id}'
    ;;
  *)
    printf '%s\n' '{"error":{"code":"invalid_command","message":"invalid command"}}' >&2
    exit 2
    ;;
esac
EOF
chmod +x "$session/bin/sleepyctl"
printf '#!%s\nexit 0\n' "$fixture_bash" >"$session/bin/sleepy-sessiond"
chmod +x "$session/bin/sleepy-sessiond"

for fixture_executable in \
  "$sdk/bin/sleepy-contract" \
  "$session/bin/sleepyctl" \
  "$validators/niri"; do
  IFS= read -r interpreter_line <"$fixture_executable"
  interpreter=${interpreter_line#\#!}
  if test "$interpreter" != "$fixture_bash" || ! test -x "$interpreter"; then
    printf 'component contract fixture has no executable interpreter: %s\n' \
      "$fixture_executable" >&2
    exit 1
  fi
done

cat >"$sources/sleepy-sdk/schemas/settings.schema.json" <<'EOF'
{"$schema":"https://json-schema.org/draft/2020-12/schema","title":"SettingsDocument","type":"object"}
EOF
cp "$sources/sleepy-sdk/schemas/settings.schema.json" \
  "$desktop/share/sleepy-desktop/contracts/settings.schema.json"

cat >"$sources/sleepy-sdk/fixtures/v1/settings/valid.json" <<'EOF'
{"schemaVersion":1,"activePresetId":"builtin.sleepy","appearanceMode":"dark"}
EOF
cat >"$sources/sleepy-sdk/fixtures/v1/settings/invalid-schema-version.json" <<'EOF'
{"schemaVersion":2,"activePresetId":"builtin.sleepy","appearanceMode":"dark"}
EOF
cat >"$sources/sleepy-sdk/fixtures/v1/preset/valid-builtin.json" <<'EOF'
{"schemaVersion":1,"id":"builtin.sleepy"}
EOF
cat >"$sources/sleepy-sdk/fixtures/v1/preset/invalid-builtin-id.json" <<'EOF'
{"schemaVersion":2,"id":"builtin.sleepy"}
EOF
cat >"$sources/sleepy-sdk/fixtures/v1/plugin/valid.json" <<'EOF'
{"schemaVersion":1,"apiVersion":1,"entrypoint":"plugin.qml"}
EOF
cat >"$sources/sleepy-sdk/fixtures/v1/plugin/invalid-api-version.json" <<'EOF'
{"schemaVersion":1,"apiVersion":2,"entrypoint":"plugin.qml"}
EOF

cat >"$artwork/share/sleepy-artwork/branding/manifest.json" <<'EOF'
{"version":1,"assets":{"branding.primaryMark":"branding/logo.svg"}}
EOF
printf '<svg xmlns="http://www.w3.org/2000/svg"/>\n' \
  >"$artwork/share/sleepy-artwork/branding/logo.svg"

cat >"$desktop/bin/sleepy-shell" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
cat >"$preview/bin/sleepy-settings-preview" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$desktop/bin/sleepy-shell" "$preview/bin/sleepy-settings-preview"

cat >"$unit/share/systemd/user/sleepy-session.service" <<EOF
[Service]
Type=notify
ExecStart=$session/bin/sleepy-sessiond
EOF

actual="$fixture/actual.json"
jq -n \
  --slurpfile reviewed "$manifest" \
  --arg sdk "$sdk" \
  --arg session "$session" \
  --arg unit "$unit" \
  --arg artwork "$artwork" \
  --arg desktop "$desktop" \
  --arg preview "$preview" \
  --arg sdkSource "$sources/sleepy-sdk" \
  '{
    schemaVersion: 1,
    system: "x86_64-linux",
    revisions: ($reviewed[0].inputs | map_values(.revision)),
    packages: {
      "sleepy-contract": {input:"sleepy-sdk", output:"sleepy-contract", path:$sdk},
      "sleepy-session": {input:"sleepy-session", output:"sleepy-session", path:$session},
      "sleepy-session-user-unit": {input:"sleepy-session", output:"sleepy-session-user-unit", path:$unit},
      "sleepy-artwork": {input:"sleepy-artwork", output:"sleepy-artwork", path:$artwork},
      "sleepy-shell": {input:"sleepy-desktop", output:"sleepy-shell", path:$desktop},
      "sleepy-settings-preview": {input:"sleepy-desktop", output:"sleepy-settings-preview", path:$preview}
    },
    defaultPackage: $desktop,
    homeManager: {
      shellPackage: $desktop,
      shellUnit: "sleepy-shell.service",
      shellExecStart: [($desktop + "/bin/sleepy-shell")],
      artworkPackage: $artwork,
      sessionPackage: $session,
      service: {
        unit: "sleepy-session.service",
        wantedBy: ["graphical-session.target"],
        partOf: ["graphical-session.target"],
        wants: ["sleepy-locker.service"],
        after: ["graphical-session.target", "dbus.socket", "sleepy-locker.service"],
        requisite: ["graphical-session.target"],
        requires: ["dbus.socket"],
        type: "notify",
        notifyAccess: "main",
        restart: "on-failure",
        runtimeDirectory: "sleepy",
        runtimeDirectoryMode: "0700",
        killSignal: "SIGINT",
        timeoutStopSec: 20,
        environment: ["PATH=/nix/store/fake-session-runtime/bin", "SLEEPY_LOCKER_SOCKET=%t/sleepy/locker.sock"],
        execStart: [($session + "/bin/sleepy-sessiond")]
      }
    },
    sources: {"sleepy-sdk": $sdkSource}
  }' >"$actual"

if ! bash "$contract" "$manifest" "$actual"; then
  printf 'component contract rejected Home Manager normalized ExecStart list\n' >&2
  exit 1
fi

m3_manifest="$fixture/desktop-m3.json"
jq '.milestone = "desktop-m3"' "$manifest" >"$m3_manifest"
if ! bash "$contract" "$m3_manifest" "$actual" >/dev/null; then
  printf 'component contract rejected the strict desktop-m3 milestone\n' >&2
  exit 1
fi

assert_rejected() {
  local name=$1
  local filter=$2
  local rejected="$fixture/rejected.json"

  jq "$filter" "$actual" >"$rejected"
  if bash "$contract" "$manifest" "$rejected" >/dev/null 2>&1; then
    printf 'component contract accepted invalid fixture: %s\n' "$name" >&2
    return 1
  fi
}

assert_rejected wrong-revision \
  '.revisions["sleepy-session"] = "0000000000000000000000000000000000000000"'
assert_rejected wrong-package-owner \
  '.packages["sleepy-shell"].input = "sleepy-session"'
assert_rejected wrong-package-output \
  '.packages["sleepy-settings-preview"].output = "default"'
assert_rejected non-graphical-service \
  '.homeManager.service.wantedBy = ["default.target"]'
assert_rejected scalar-session-exec-start \
  '.homeManager.service.execStart = .homeManager.service.execStart[0]'
assert_rejected unbounded-session-path \
  '.homeManager.service.environment = ["PATH=/run/current-system/sw/bin"]'
assert_rejected wrong-runtime-mode \
  '.homeManager.service.runtimeDirectoryMode = "0755"'
assert_rejected generic-quickshell-runner \
  '.homeManager.shellExecStart = ["/nix/store/fake-quickshell/bin/quickshell"]'
assert_rejected generic-quickshell-unit \
  '.homeManager.shellUnit = "quickshell.service"'
assert_rejected wrong-notify-access '.homeManager.service.notifyAccess = "all"'
assert_rejected unexpected-root-source '.sources.root = "/does-not-exist"'

cp "$session/bin/sleepyctl" "$fixture/sleepyctl.good"
printf '#!%s\n' "$fixture_bash" >"$session/bin/sleepyctl"
cat >>"$session/bin/sleepyctl" <<'EOF'
printf '{}\n'
EOF
chmod +x "$session/bin/sleepyctl"
if bash "$contract" "$manifest" "$actual" >/dev/null 2>&1; then
  printf 'component contract accepted a broken sleepyctl JSON contract\n' >&2
  exit 1
fi
cp "$fixture/sleepyctl.good" "$session/bin/sleepyctl"

cp "$artwork/share/sleepy-artwork/branding/manifest.json" \
  "$fixture/artwork-manifest.good"
printf '%s\n' '{"version":1,"assets":{}}' \
  >"$artwork/share/sleepy-artwork/branding/manifest.json"
if bash "$contract" "$manifest" "$actual" >/dev/null 2>&1; then
  printf 'component contract accepted artwork without branding.primaryMark\n' >&2
  exit 1
fi
cp "$fixture/artwork-manifest.good" \
  "$artwork/share/sleepy-artwork/branding/manifest.json"

printf '%s\n' '{"title":"incompatible"}' \
  >"$desktop/share/sleepy-desktop/contracts/settings.schema.json"
if bash "$contract" "$manifest" "$actual" >/dev/null 2>&1; then
  printf 'component contract accepted an incompatible desktop SDK schema\n' >&2
  exit 1
fi

printf 'component contract self-test: ok\n'
