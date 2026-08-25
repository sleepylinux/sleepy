#!/usr/bin/env bash
set -euo pipefail

for required_command in cmp find jq mktemp sha256sum; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'component contract: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

if test "$#" -ne 2; then
  printf 'usage: %s <reviewed-manifest.json> <actual-contract.json>\n' \
    "${0##*/}" >&2
  exit 2
fi

manifest=$1
actual=$2

jq -e '
  .schemaVersion == 1 and
  (.milestone == "desktop-m1" or .milestone == "desktop-m2" or .milestone == "desktop-m3") and
  (.inputs | keys == ["sleepy-artwork", "sleepy-desktop", "sleepy-sdk", "sleepy-session"]) and
  all(.inputs | to_entries[];
    (.value.revision | type == "string" and test("^[0-9a-f]{40}$")) and
    .value.url == ("github:sleepylinux/" + .key + "/" + .value.revision)
  ) and
  (.rootPackages | type == "object") and
  .defaultPackage == "sleepy-shell"
' "$manifest" >/dev/null

jq -e --slurpfile reviewed "$manifest" '
  . as $actual |
  .schemaVersion == 1 and
  (.system | type == "string" and length > 0) and
  .revisions == ($reviewed[0].inputs | map_values(.revision)) and
  ([
    $reviewed[0].rootPackages | to_entries[] as $package |
    $actual.packages[$package.key].input == $package.value.input and
    $actual.packages[$package.key].output == $package.value.output and
    ($actual.packages[$package.key].path | type == "string" and length > 0)
  ] | all) and
  .defaultPackage == .packages[$reviewed[0].defaultPackage].path and
  .homeManager.shellPackage == .packages["sleepy-shell"].path and
  .homeManager.quickshellConfig ==
    (.packages["sleepy-shell"].path + "/share/sleepy-desktop") and
  .homeManager.artworkPackage == .packages["sleepy-artwork"].path and
  .homeManager.sessionPackage == .packages["sleepy-session"].path and
  .homeManager.service.unit == "sleepy-session.service" and
  .homeManager.service.wantedBy == ["graphical-session.target"] and
  .homeManager.service.partOf == ["graphical-session.target"] and
  .homeManager.service.after == ["graphical-session.target", "dbus.socket"] and
  .homeManager.service.requisite == ["graphical-session.target"] and
  .homeManager.service.requires == ["dbus.socket"] and
  .homeManager.service.type == "simple" and
  .homeManager.service.restart == "on-failure" and
  .homeManager.service.runtimeDirectory == "sleepy" and
  .homeManager.service.runtimeDirectoryMode == "0700" and
  .homeManager.service.killSignal == "SIGINT" and
  .homeManager.service.timeoutStopSec == 20 and
  (.homeManager.service.environment | length == 1) and
  (.homeManager.service.environment[0] | startswith("PATH=/nix/store/")) and
  .homeManager.service.execStart ==
    [(.packages["sleepy-session"].path + "/bin/sleepy-sessiond")] and
  (.sources["sleepy-sdk"] | type == "string" and length > 0) and
  (.sources.root | type == "string" and length > 0) and
  (.validators.niri | type == "string" and startswith("/") and length > 1)
' "$actual" >/dev/null

sdk=$(jq -er '.packages["sleepy-contract"].path' "$actual")
session=$(jq -er '.packages["sleepy-session"].path' "$actual")
unit=$(jq -er '.packages["sleepy-session-user-unit"].path' "$actual")
artwork=$(jq -er '.packages["sleepy-artwork"].path' "$actual")
desktop=$(jq -er '.packages["sleepy-shell"].path' "$actual")
preview=$(jq -er '.packages["sleepy-settings-preview"].path' "$actual")
sdk_source=$(jq -er '.sources["sleepy-sdk"]' "$actual")
root_source=$(jq -er '.sources.root' "$actual")
niri_validator=$(jq -er '.validators.niri' "$actual")

sdk_cli="$sdk/bin/sleepy-contract"
session_cli="$session/bin/sleepyctl"
test -x "$sdk_cli"
test -x "$session_cli"
test -x "$session/bin/sleepy-sessiond"
test -x "$desktop/bin/sleepy-shell"
test -x "$preview/bin/sleepy-settings-preview"
test -f "$unit/share/systemd/user/sleepy-session.service"
test -x "$niri_validator"

for kind in settings preset plugin; do
  for fixture in "$sdk_source/fixtures/v1/$kind"/valid*.json; do
    test -f "$fixture"
    "$sdk_cli" validate "$kind" "$fixture" >/dev/null
  done

  for fixture in "$sdk_source/fixtures/v1/$kind"/invalid*.json; do
    test -f "$fixture"
    if "$sdk_cli" validate "$kind" "$fixture" >/dev/null 2>&1; then
      printf 'SDK validator accepted invalid %s fixture: %s\n' \
        "$kind" "$fixture" >&2
      exit 1
    fi
  done
done

runtime=$(mktemp -d /tmp/sleepy-component-runtime.XXXXXX)
trap 'rm -rf -- "$runtime"' EXIT
mkdir -p "$runtime/home" "$runtime/config/niri"
cp "$root_source/modules/home/niri/config/"*.kdl "$runtime/config/niri/"
test "$(find "$runtime/config/niri" -maxdepth 1 -type f -name '*.kdl' | wc -l)" -eq 6

run_sleepyctl() {
  HOME="$runtime/home" \
    XDG_CONFIG_HOME="$runtime/config" \
    XDG_STATE_HOME="$runtime/state" \
    SLEEPY_NIRI_VALIDATOR="$niri_validator" \
    "$session_cli" "$@"
}

settings_output="$runtime/settings.json"
run_sleepyctl settings show >"$settings_output"
jq -e '
  .schemaVersion == 1 and
  .activePresetId == "builtin.sleepy" and
  (.appearanceMode | type == "string") and
  (.reducedMotion | type == "boolean")
' "$settings_output" >/dev/null
"$sdk_cli" validate settings "$settings_output" >/dev/null

settings_state="$runtime/config/sleepy/settings.json"
test -f "$settings_state"
jq '.webSearchEnabled = false' "$settings_state" >"$runtime/user-settings.json"
mv "$runtime/user-settings.json" "$settings_state"
before_hash=$(sha256sum "$settings_state" | cut -d' ' -f1)
run_sleepyctl settings show >"$settings_output"
after_hash=$(sha256sum "$settings_state" | cut -d' ' -f1)
test "$before_hash" = "$after_hash"
jq -e '.webSearchEnabled == false' "$settings_output" >/dev/null
"$sdk_cli" validate settings "$settings_output" >/dev/null

presets_output="$runtime/presets.json"
run_sleepyctl presets list >"$presets_output"
jq -e '
  (.presets | type == "array") and
  any(.presets[]; .id == "builtin.sleepy" and .origin == "builtin")
' "$presets_output" >/dev/null

duplicate_output="$runtime/duplicate.json"
run_sleepyctl presets duplicate builtin.sleepy 'Contract copy' \
  >"$duplicate_output"
duplicate_id=$(jq -er '
  .preset.id |
  select(type == "string" and . != "builtin.sleepy" and length > 0)
' "$duplicate_output")

rename_output="$runtime/rename.json"
run_sleepyctl presets rename "$duplicate_id" 'Contract renamed' \
  >"$rename_output"
jq -e --arg id "$duplicate_id" '
  .preset.id == $id and .preset.name == "Contract renamed"
' "$rename_output" >/dev/null

test ! -e "$runtime/config/niri/sleepy-user-bindings.kdl"
test ! -e "$runtime/state/sleepy/bindings-transaction.json"

if run_sleepyctl presets activate "$duplicate_id" \
  >"$runtime/unexpected-activate.json" 2>"$runtime/apply-required.json"; then
  printf 'sleepyctl retained the settings-only activation bypass\n' >&2
  exit 1
fi
jq -e '.error.code == "apply_required"' "$runtime/apply-required.json" >/dev/null

activate_output="$runtime/activate.json"
run_sleepyctl presets activate "$duplicate_id" --apply >"$activate_output"
jq -e --arg id "$duplicate_id" '
  .activePresetId == $id and .status == "reloadPending"
' "$activate_output" >/dev/null
test -f "$runtime/config/niri/sleepy-user-bindings.kdl"
test -f "$runtime/state/sleepy/bindings-transaction.json"

immutable_error="$runtime/immutable-error.json"
if run_sleepyctl presets rename builtin.sleepy Nope \
  >"$runtime/unexpected.json" 2>"$immutable_error"; then
  printf 'sleepyctl mutated the immutable built-in preset\n' >&2
  exit 1
fi
jq -e '.error.code == "immutable_preset"' "$immutable_error" >/dev/null
test ! -e "$runtime/home/.config/sleepy/settings.json"
test ! -e "$runtime/home/.local/state/sleepy/presets.json"

artwork_manifest="$artwork/share/sleepy-artwork/branding/manifest.json"
primary_mark_relative=$(jq -er '
  select(.version == 1) |
  .assets["branding.primaryMark"] |
  select(type == "string" and length > 0)
' "$artwork_manifest")
case "$primary_mark_relative" in
  /* | *../* | */.. | ..)
    printf 'branding.primaryMark is not package-relative: %s\n' \
      "$primary_mark_relative" >&2
    exit 1
    ;;
esac
test -f "$artwork/share/sleepy-artwork/$primary_mark_relative"

cmp \
  "$sdk_source/schemas/settings.schema.json" \
  "$desktop/share/sleepy-desktop/contracts/settings.schema.json"

printf 'component contract: ok\n'
