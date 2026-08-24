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
    case "$phase" in
      prepared|presetCommitted|settingsCommitted) variant=old ;;
      bindingsCommitted|reloadPending|reloadConfirmed) variant=new ;;
    esac
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
    case "$phase" in
      prepared|presetCommitted|settingsCommitted)
        jq -e '.result.status == "reloadPending" and
          .cleanup.status == "rolledBackConfirmed"' <<<"$output" >/dev/null
        ;;
      bindingsCommitted|reloadPending)
        jq -e '.result.status == "reloadPending" and
          .cleanup.status == "committed"' <<<"$output" >/dev/null
        ;;
      reloadConfirmed)
        jq -e '.result.status == "committed" and .cleanup == null' \
          <<<"$output" >/dev/null
        ;;
    esac
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

  helper_root="$TMPDIR/helper-adversarial"
  mkdir -p "$helper_root/config/sleepy" "$helper_root/config/niri" \
    "$helper_root/state/sleepy"
  for file in \
    "$helper_root/config/sleepy/settings.json" \
    "$helper_root/state/sleepy/presets.json" \
    "$helper_root/config/niri/sleepy-user-bindings.kdl"; do
    printf 'live\n' >"$file"
    printf 'old\n' >"$file.sleepy-transaction.old"
    printf 'new\n' >"$file.sleepy-transaction.new"
  done
  printf '{}\n' >"$helper_root/state/sleepy/bindings-transaction.json"
  printf 'prepared\n' >"$helper_root/fault.must-consume"

  race_root="$TMPDIR/helper-parent-race"
  cp -a "$helper_root" "$race_root"
  mkdir "$race_root/attacker-niri"
  printf 'attacker-marker\n' >"$race_root/attacker-niri/marker"
  (
    for _attempt in $(seq 1 500); do
      if mv "$race_root/config/niri" "$race_root/config/niri.real" 2>/dev/null; then
        ln -s "$race_root/attacker-niri" "$race_root/config/niri"
        rm "$race_root/config/niri"
        mv "$race_root/config/niri.real" "$race_root/config/niri"
      fi
    done
  ) &
  swapper=$!
  printf '{}\n' | ${runner.fsHelper}/bin/sleepy-journal-fs prepare \
    "$race_root" >/dev/null 2>&1 || true
  wait "$swapper"
  test "$(cat "$race_root/attacker-niri/marker")" = attacker-marker
  test "$(find "$race_root/attacker-niri" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1

  printf 'do-not-truncate\n' >"$helper_root/victim"
  ln -s "$helper_root/victim" \
    "$helper_root/state/sleepy/.bindings-transaction.runner.prepare.tmp"
  if printf '{}\n' | ${runner.fsHelper}/bin/sleepy-journal-fs prepare \
    "$helper_root" >/dev/null 2>&1; then
    echo 'filesystem helper accepted a swapped deterministic staging path' >&2
    exit 1
  fi
  test "$(cat "$helper_root/victim")" = do-not-truncate
  test "$(cat "$helper_root/fault.must-consume")" = prepared
  test "$(find "$helper_root/config" "$helper_root/state" -type f \
    -name '*.00000000-0000-4000-8000-000000000001.*' | wc -l)" -eq 0
  for fixture in \
    "$helper_root/config/sleepy/settings.json" \
    "$helper_root/state/sleepy/presets.json" \
    "$helper_root/config/niri/sleepy-user-bindings.kdl"; do
    test "$(cat "$fixture.sleepy-transaction.old")" = old
    test "$(cat "$fixture.sleepy-transaction.new")" = new
  done
  rm "$helper_root/state/sleepy/.bindings-transaction.runner.prepare.tmp"

  rm "$helper_root/config/sleepy/settings.json.sleepy-transaction.old"
  ln -s "$helper_root/missing" \
    "$helper_root/config/sleepy/settings.json.sleepy-transaction.old"
  rm "$helper_root/state/sleepy/bindings-transaction.json"
  if ${runner.fsHelper}/bin/sleepy-journal-fs cleanup "$helper_root" \
    >/dev/null 2>&1; then
    echo 'filesystem helper accepted a dangling fixture sidecar' >&2
    exit 1
  fi
  test -L "$helper_root/config/sleepy/settings.json.sleepy-transaction.old"

  touch "$out"
''
