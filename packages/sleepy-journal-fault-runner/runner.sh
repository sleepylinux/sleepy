# shellcheck shell=bash disable=SC2015,SC2016
set -euo pipefail
umask 077

die() {
  printf 'sleepy-journal-fault-runner: %s\n' "$*" >&2
  exit 2
}

test "$#" -eq 1 || die 'exactly one phase argument is required'
phase=$1
case "$phase" in
  prepared|presetCommitted|settingsCommitted|bindingsCommitted|reloadPending|reloadConfirmed) ;;
  *) die 'invalid journal phase' ;;
esac

test "${SLEEPY_FAULT_PHASE-}" = "$phase" || die 'phase environment mismatch'
test -n "${HOME-}" && test -n "${XDG_CONFIG_HOME-}" && test -n "${XDG_STATE_HOME-}" ||
  die 'HOME and XDG roots are required'
test -n "${SLEEPY_FAULT_CANARY-}" && test -n "${SLEEPY_FAULT_FIXTURE_MANIFEST-}" ||
  die 'fault fixture environment is required'

for root in "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"; do
  case "$root" in
    /*) ;;
    *) die 'XDG roots must be absolute' ;;
  esac
  test -d "$root" && ! test -L "$root" || die 'XDG root is not a real directory'
  test "$(@coreutils@/realpath -e -- "$root")" = "$root" || die 'XDG root is not canonical'
done

runtime_root=$(@coreutils@/dirname -- "$XDG_CONFIG_HOME")
test "$XDG_CONFIG_HOME" = "$runtime_root/config" || die 'unexpected config root'
test "$XDG_STATE_HOME" = "$runtime_root/state" || die 'unexpected state root'
test "$HOME" = "$runtime_root/home" || die 'unexpected home root'
manifest=$SLEEPY_FAULT_FIXTURE_MANIFEST
canary=$SLEEPY_FAULT_CANARY
journal=$XDG_STATE_HOME/sleepy/bindings-transaction.json
test "$manifest" = "$runtime_root/fault-fixture.json" || die 'unexpected manifest path'
test "$canary" = "$runtime_root/fault.must-consume" || die 'unexpected canary path'

validate_file() {
  local path=$1
  test -f "$path" && ! test -L "$path" || die "unsafe fixture file: $path"
  test "$(@coreutils@/stat -c '%u:%h' -- "$path")" = "$(@coreutils@/id -u):1" ||
    die "fixture ownership or link count is unsafe: $path"
}

validate_directory() {
  local path=$1 mode
  test -d "$path" && ! test -L "$path" || die "unsafe fixture directory: $path"
  test "$(@coreutils@/realpath -e -- "$path")" = "$path" ||
    die "fixture directory is not canonical: $path"
  test "$(@coreutils@/stat -c '%u' -- "$path")" = "$(@coreutils@/id -u)" ||
    die "fixture directory has the wrong owner: $path"
  mode=$(@coreutils@/stat -c '%a' -- "$path")
  (( (8#$mode & 0022) == 0 )) || die "fixture directory is group/world writable: $path"
}

validate_directory "$runtime_root"
validate_directory "$XDG_CONFIG_HOME/sleepy"
validate_directory "$XDG_CONFIG_HOME/niri"
validate_directory "$XDG_STATE_HOME/sleepy"
validate_file "$manifest"
validate_file "$canary"
validate_file "$journal"
test "$(@coreutils@/cat -- "$canary")" = "$phase" || die 'canary phase mismatch'

case "$phase" in
  prepared|presetCommitted|settingsCommitted) expected_variant=old ;;
  bindingsCommitted|reloadPending|reloadConfirmed) expected_variant=new ;;
esac
@jq@ -e --arg phase "$phase" --arg journal "$journal" --arg expected "$expected_variant" '
  type == "object" and keys == ["expectedVariant","journal","phase","schemaVersion"] and
  .schemaVersion == 1 and .phase == $phase and .journal == $journal and
  .expectedVariant == $expected
' "$manifest" >/dev/null || die 'invalid fixture manifest'

settings=$XDG_CONFIG_HOME/sleepy/settings.json
presets=$XDG_STATE_HOME/sleepy/presets.json
bindings=$XDG_CONFIG_HOME/niri/sleepy-user-bindings.kdl
@jq@ -e \
  --arg phase "$phase" \
  --arg settings "$settings" --arg presets "$presets" --arg bindings "$bindings" '
  def artifact($path):
    type == "object" and
    keys == ["newPath","newSha256","oldPath","oldSha256","path"] and
    .path == $path and .oldPath == ($path + ".sleepy-transaction.old") and
    .newPath == ($path + ".sleepy-transaction.new") and
    (.oldSha256 | test("^[0-9a-f]{64}$")) and
    (.newSha256 | test("^[0-9a-f]{64}$"));
  type == "object" and keys == ["artifacts","phase","schemaVersion"] and
  .schemaVersion == 1 and .phase == $phase and
  (.artifacts | type == "object" and keys == ["bindings","presets","settings"]) and
  (.artifacts.settings | artifact($settings)) and
  (.artifacts.presets | artifact($presets)) and
  (.artifacts.bindings | artifact($bindings))
' "$journal" >/dev/null || die 'invalid transaction journal'

for live in "$settings" "$presets" "$bindings"; do
  validate_file "$live"
  validate_file "$live.sleepy-transaction.old"
  validate_file "$live.sleepy-transaction.new"
done

for label in settings presets bindings; do
  case "$label" in
    settings) live=$settings ;;
    presets) live=$presets ;;
    bindings) live=$bindings ;;
  esac
  for variant in old new; do
    expected_hash=$(@jq@ -er --arg label "$label" --arg field "${variant}Sha256" \
      '.artifacts[$label][$field]' "$journal")
    actual_hash=$(@coreutils@/sha256sum -- "$live.sleepy-transaction.$variant")
    actual_hash=${actual_hash%% *}
    test "$actual_hash" = "$expected_hash" || die 'transaction sidecar hash mismatch'
  done
done

transaction_id=00000000-0000-4000-8000-000000000001
recovery_target=candidate
@fshelper@ consume "$runtime_root" "$phase"
test ! -e "$canary" && ! test -L "$canary" || die 'fault canary was not consumed'

@jq@ -n --arg phase "$phase" --arg transactionId "$transaction_id" \
  --arg recoveryTarget "$recovery_target" \
  --arg settings "$settings" --arg presets "$presets" --arg bindings "$bindings" \
  --slurpfile fixture "$journal" '
  def artifact($kind; $destination; $source): {
    kind: $kind,
    destination: $destination,
    oldArtifact: (($destination | sub("/[^/]+$"; "")) + "/." +
      ($destination | split("/") | last) + "." + $transactionId + ".old"),
    newArtifact: (($destination | sub("/[^/]+$"; "")) + "/." +
      ($destination | split("/") | last) + "." + $transactionId + ".new"),
    oldExisted: true,
    oldHash: $source.oldSha256,
    newHash: $source.newSha256
  };
  {
    schemaVersion: 1,
    transactionId: $transactionId,
    phase: $phase,
    recoveryTarget: $recoveryTarget,
    sidecarsComplete: true,
    activePresetId: "candidate",
    previousActivePresetId: "baseline",
    artifacts: [
      artifact("preset"; $presets; $fixture[0].artifacts.presets),
      artifact("settings"; $settings; $fixture[0].artifacts.settings),
      artifact("bindings"; $bindings; $fixture[0].artifacts.bindings)
    ]
  }
' | @fshelper@ prepare "$runtime_root"

run_reconcile() {
  @coreutils@/env -i \
    HOME="$HOME" \
    XDG_CONFIG_HOME="$XDG_CONFIG_HOME" \
    XDG_STATE_HOME="$XDG_STATE_HOME" \
    @sleepyctl@ bindings reconcile
}

reconcile_output=$(run_reconcile) || die 'product reconciliation failed'
@jq@ -e 'type == "object"' <<<"$reconcile_output" >/dev/null ||
  die 'product reconciliation returned non-object JSON'

cleanup_output=null
if test "$phase" != reloadConfirmed; then
  validate_file "$journal"
  @jq@ '.phase = "reloadConfirmed"' "$journal" |
    @fshelper@ replace-journal "$runtime_root"
  cleanup_output=$(run_reconcile) || die 'product reconciliation cleanup failed'
  @jq@ -e 'type == "object"' <<<"$cleanup_output" >/dev/null ||
    die 'product reconciliation cleanup returned non-object JSON'
fi

test ! -e "$journal" && ! test -L "$journal" || die 'product left transaction journal behind'
@fshelper@ cleanup "$runtime_root"

@jq@ -n --arg phase "$phase" --argjson result "$reconcile_output" \
  --argjson cleanup "$cleanup_output" \
  '{faultPhase:$phase,faultInjected:true,reconcileInvoked:true,result:$result,cleanup:$cleanup}'
