{pkgs, runner}:
pkgs.runCommand "sleepy-journal-fault-runner-check" {
  nativeBuildInputs = [pkgs.coreutils pkgs.jq];
} ''
  test -x ${runner}/bin/sleepy-journal-fault-runner
  test "${runner.meta.license.spdxId}" = GPL-3.0-only

  if ${runner}/bin/sleepy-journal-fault-runner prepared >/dev/null 2>&1; then
    echo 'runner accepted missing environment' >&2
    exit 1
  fi
  if SLEEPY_FAULT_PHASE=bogus ${runner}/bin/sleepy-journal-fault-runner bogus >/dev/null 2>&1; then
    echo 'runner accepted invalid phase' >&2
    exit 1
  fi

  run_phase() {
    phase=$1
    root="$TMPDIR/$phase"
    mkdir -p "$root/home" "$root/config/sleepy" "$root/config/niri" "$root/state/sleepy"
    settings="$root/config/sleepy/settings.json"
    presets="$root/state/sleepy/presets.json"
    bindings="$root/config/niri/sleepy-user-bindings.kdl"
    printf '%s\n' '{"schemaVersion":1,"activePresetId":"baseline"}' >"$settings.old.expected"
    printf '%s\n' '{"schemaVersion":1,"activePresetId":"candidate"}' >"$settings.new.expected"
    printf '%s\n' '{"schemaVersion":1,"presets":[{"id":"baseline"}]}' >"$presets.old.expected"
    printf '%s\n' '{"schemaVersion":1,"presets":[{"id":"candidate"}]}' >"$presets.new.expected"
    printf '%s\n' 'binds { Mod+Return { spawn "ghostty"; } }' >"$bindings.old.expected"
    printf '%s\n' 'binds { Mod+Space { spawn "fuzzel"; } }' >"$bindings.new.expected"
    for live in "$settings" "$presets" "$bindings"; do
      cp "$live.old.expected" "$live.sleepy-transaction.old"
      cp "$live.new.expected" "$live.sleepy-transaction.new"
      cp "$live.old.expected" "$live"
    done
    case "$phase" in
      presetCommitted) cp "$presets.new.expected" "$presets" ;;
      settingsCommitted)
        cp "$presets.new.expected" "$presets"
        cp "$settings.new.expected" "$settings"
        ;;
      bindingsCommitted|reloadPending|reloadConfirmed)
        cp "$presets.new.expected" "$presets"
        cp "$settings.new.expected" "$settings"
        cp "$bindings.new.expected" "$bindings"
        ;;
    esac
    journal="$root/state/sleepy/bindings-transaction.json"
    jq -n --arg phase "$phase" \
      --arg settings "$settings" --arg presets "$presets" --arg bindings "$bindings" \
      --arg settingsOld "$settings.sleepy-transaction.old" --arg settingsNew "$settings.sleepy-transaction.new" \
      --arg presetsOld "$presets.sleepy-transaction.old" --arg presetsNew "$presets.sleepy-transaction.new" \
      --arg bindingsOld "$bindings.sleepy-transaction.old" --arg bindingsNew "$bindings.sleepy-transaction.new" \
      --arg settingsOldSha "$(sha256sum "$settings.old.expected" | cut -d' ' -f1)" \
      --arg settingsNewSha "$(sha256sum "$settings.new.expected" | cut -d' ' -f1)" \
      --arg presetsOldSha "$(sha256sum "$presets.old.expected" | cut -d' ' -f1)" \
      --arg presetsNewSha "$(sha256sum "$presets.new.expected" | cut -d' ' -f1)" \
      --arg bindingsOldSha "$(sha256sum "$bindings.old.expected" | cut -d' ' -f1)" \
      --arg bindingsNewSha "$(sha256sum "$bindings.new.expected" | cut -d' ' -f1)" \
      '{schemaVersion:1,phase:$phase,artifacts:{
        settings:{path:$settings,oldPath:$settingsOld,newPath:$settingsNew,oldSha256:$settingsOldSha,newSha256:$settingsNewSha},
        presets:{path:$presets,oldPath:$presetsOld,newPath:$presetsNew,oldSha256:$presetsOldSha,newSha256:$presetsNewSha},
        bindings:{path:$bindings,oldPath:$bindingsOld,newPath:$bindingsNew,oldSha256:$bindingsOldSha,newSha256:$bindingsNewSha}}}' >"$journal"
    variant=old
    test "$phase" = reloadConfirmed && variant=new
    jq -n --arg phase "$phase" --arg journal "$journal" --arg expected "$variant" \
      '{schemaVersion:1,phase:$phase,journal:$journal,expectedVariant:$expected}' >"$root/fault-fixture.json"
    printf '%s\n' "$phase" >"$root/fault.must-consume"

    if test "$phase" = prepared; then
      cp "$root/fault-fixture.json" "$root/fault-fixture.valid.json"
      jq '.unexpected = true' "$root/fault-fixture.valid.json" >"$root/fault-fixture.json"
      if HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_STATE_HOME="$root/state" \
        SLEEPY_FAULT_PHASE="$phase" SLEEPY_FAULT_CANARY="$root/fault.must-consume" \
        SLEEPY_FAULT_FIXTURE_MANIFEST="$root/fault-fixture.json" \
        ${runner}/bin/sleepy-journal-fault-runner "$phase" >/dev/null 2>&1; then
        echo 'runner accepted malformed manifest' >&2
        exit 1
      fi
      test -f "$root/fault.must-consume"
      cp "$root/fault-fixture.valid.json" "$root/fault-fixture.json"
      if HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_STATE_HOME="$root/state" \
        SLEEPY_FAULT_PHASE=reloadPending SLEEPY_FAULT_CANARY="$root/fault.must-consume" \
        SLEEPY_FAULT_FIXTURE_MANIFEST="$root/fault-fixture.json" \
        ${runner}/bin/sleepy-journal-fault-runner "$phase" >/dev/null 2>&1; then
        echo 'runner accepted mismatched phase environment' >&2
        exit 1
      fi
      test -f "$root/fault.must-consume"
      mv "$root/config/niri" "$root/config/niri.real"
      ln -s niri.real "$root/config/niri"
      if HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_STATE_HOME="$root/state" \
        SLEEPY_FAULT_PHASE="$phase" SLEEPY_FAULT_CANARY="$root/fault.must-consume" \
        SLEEPY_FAULT_FIXTURE_MANIFEST="$root/fault-fixture.json" \
        ${runner}/bin/sleepy-journal-fault-runner "$phase" >/dev/null 2>&1; then
        echo 'runner accepted a symlinked artifact parent' >&2
        exit 1
      fi
      test -f "$root/fault.must-consume"
      rm "$root/config/niri"
      mv "$root/config/niri.real" "$root/config/niri"
    fi

    output=$(HOME="$root/home" XDG_CONFIG_HOME="$root/config" XDG_STATE_HOME="$root/state" \
      SLEEPY_FAULT_PHASE="$phase" SLEEPY_FAULT_CANARY="$root/fault.must-consume" \
      SLEEPY_FAULT_FIXTURE_MANIFEST="$root/fault-fixture.json" \
      ${runner}/bin/sleepy-journal-fault-runner "$phase")
    jq -e --arg phase "$phase" \
      'type == "object" and .faultPhase == $phase and .faultInjected and .reconcileInvoked' \
      <<<"$output" >/dev/null
    for live in "$settings" "$presets" "$bindings"; do
      cmp "$live.$variant.expected" "$live"
      test ! -e "$live.sleepy-transaction.old"
      test ! -e "$live.sleepy-transaction.new"
    done
    test ! -e "$journal"
    test ! -e "$root/fault.must-consume"
  }

  for phase in prepared presetCommitted settingsCommitted bindingsCommitted reloadPending reloadConfirmed; do
    run_phase "$phase"
  done

  touch "$out"
''
