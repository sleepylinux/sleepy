#!/usr/bin/env bash
# Packaged with fixed executable/theme paths by the NixOS module.
set -euo pipefail
export DIALOGRC=@dialogrc@

usage() {
  printf '%s\n' 'sleepy-system [menu | status | generations | rebuild | rollback | update | update-status | recover-update]' \
    'rebuild applies the configuration already saved in /etc/nixos; it does not download a new Sleepy version.'
}

system_status() {
  local label path resolved identity
  for label in 'Current system' 'Booted system' 'Selected system profile'; do
    case "$label" in
      'Current system') path=/run/current-system ;;
      'Booted system') path=/run/booted-system ;;
      *) path=/nix/var/nix/profiles/system ;;
    esac
    resolved=$(readlink -e "$path") || resolved='unavailable'
    if test "${1:-full}" = brief; then
      case "$resolved" in
        /nix/store/*)
          resolved=${resolved##*/}
          identity=${resolved%%-*}
          resolved="${resolved#*-} [${identity:0:8}]"
          ;;
      esac
    fi
    printf '%s: %s\n' "$label" "${resolved:-unavailable}"
  done
}

list_generations() {
  local profile=/nix/var/nix/profiles/system
  local directory entry generation selected timestamp marker
  directory=${profile%/*}
  if ! test -r "$directory" || ! test -x "$directory"; then
    printf 'Cannot read saved system generations.\n' >&2
    return 1
  fi
  selected=$(readlink "$profile") || selected=
  # nix-env --list-generations takes a write lock on the system profile.
  # Reading the generation symlinks needs no lock or administrative privilege.
  for entry in "$profile"-*-link; do
    test -L "$entry" || continue
    generation=${entry#"$profile"-}
    generation=${generation%-link}
    [[ "$generation" =~ ^[0-9]+$ ]] || continue
    timestamp=$(stat -c %Y -- "$entry") || return $?
    timestamp=$(date -d "@$timestamp" '+%Y-%m-%d %H:%M:%S') || return $?
    marker=
    case "$selected" in "$entry"|"${entry##*/}") marker='(current)' ;; esac
    printf '%s  %s  %s\n' "$generation" "$timestamp" "$marker"
  done | sort -n
}

operation_output() {
  case "$1" in
    prepare|recover-update)
      # Preserve non-JSON diagnostics (including normal sudo errors). Strip
      # terminal control bytes from display only; the private log stays raw.
      jq --unbuffered -Rr '
        (fromjson? // .)
        | if type == "object" and (.message | type) == "string"
          then "\(.progress // 0)%  \(.stage // "update"): \(.message)"
          elif type == "string" then . else tostring end
        | gsub("[\u0000-\u001f\u007f]"; " ")'
      ;;
    *) cat ;;
  esac
}

run_saved() {
  local operation=$1 log_directory log status source stage_status executable=@rebuild@
  local -a args pipeline_status
  case "$operation" in
    rebuild)
      args=(switch --flake /etc/nixos#installed)
      source=$(@update@ source) || return $?
      if test -n "$source"; then
        if ! [[ "$source" =~ ^/nix/store/[0-9a-df-np-sv-z]{32}-[a-zA-Z0-9+._?=-]+$ ]]; then
          printf 'Selected source metadata is invalid; no rebuild started.\n' >&2
          return 1
        fi
        args+=(--override-input sleepy "path:$source" --no-write-lock-file)
      fi
      ;;
    rollback) args=(switch --rollback) ;;
    prepare) executable=@update@; args=(prepare "$2") ;;
    recover-update) executable=@update@; args=(recover) ;;
    update-status) executable=@update@; args=(status) ;;
    *) return 2 ;;
  esac
  umask 077
  log_directory="${XDG_STATE_HOME:-$HOME/.local/state}/sleepy/system"
  # This function is also called in an if condition, where Bash suppresses
  # errexit. Guard prerequisites explicitly before invoking any system change.
  mkdir -p "$log_directory" || {
    status=$?
    printf 'Cannot create diagnostic directory; no system change started.\n' >&2
    return "$status"
  }
  log=$(mktemp "$log_directory/$operation.XXXXXXXX.log") || {
    status=$?
    printf 'Cannot create diagnostic log; no system change started.\n' >&2
    return "$status"
  }
  printf '%s\n' "Sleepy: $operation. Administrator authentication may be requested." \
    "Live progress follows. Diagnostics: $log"
  # sudo uses its normal terminal prompt. Only command output is recorded;
  # never read or redirect terminal input, password prompts or credentials.
  set +e
  sudo "$executable" "${args[@]}" 2>&1 | tee "$log" | operation_output "$operation"
  pipeline_status=("${PIPESTATUS[@]}")
  set -e
  status=${pipeline_status[0]}
  for stage_status in "${pipeline_status[@]:1}"; do
    if test "$status" -eq 0; then status=$stage_status; fi
  done
  if test "$status" -eq 0; then
    printf 'Sleepy: %s completed. Diagnostics: %s\n' "$operation" "$log"
  else
    printf 'Sleepy: %s failed (exit %s). Diagnostics: %s\n' "$operation" "$status" "$log" >&2
  fi
  return "$status"
}

confirm_update() {
  local status
  if dialog --title ' Confirm system change ' --defaultno --yesno "$1" 17 76; then
    return 0
  else
    status=$?
    case "$status" in 1|255) return 1 ;; *) return "$status" ;; esac
  fi
}

update_result() {
  local operation=$1 status summary
  shift
  dialog --clear
  if run_saved "$operation" "$@"; then status=0; else status=$?; fi
  if test "$status" -ne 0; then
    summary="The operation stopped (exit $status). Read the private diagnostic log shown above. Use Update status before retrying; Recover incomplete update can restore a saved interrupted transaction."
  elif test "$operation" = prepare; then
    summary='The candidate is prepared for the next boot. Restart when ready. This does not confirm that the new system boots successfully. Your personal files are not rolled back.'
  elif test "$operation" = recover-update; then
    summary='Recovery finished. Check Update status and the selected system generation before restarting. This does not restore personal files.'
  else
    summary='Update status is shown in the terminal above, with its private diagnostic log path.'
  fi
  dialog --title ' Sleepy update ' --msgbox "$summary" 15 76 || true
  return "$status"
}

choose_update() {
  local snapshot line id label choice status found= label_selected=
  local -a items=()
  local -A labels=()
  # Capture the command's status before reading TSV. Process substitution would
  # lose a failed catalogue read and could offer a partial result for approval.
  snapshot=$(@update@ candidates) || return $?
  if test -z "$snapshot"; then
    dialog --title ' Choose an update ' --msgbox \
      'No approved candidates are installed. Saved settings can still be applied. No release channel has been selected.' 12 76
    return 0
  fi
  while IFS= read -r line; do
    if [[ "$line" != *$'\t'* ]]; then return 1; fi
    id=${line%%$'\t'*}
    label=${line#*$'\t'}
    if ! [[ "$id" =~ ^[a-z0-9][a-z0-9._-]{0,63}$ ]] ||
       test "$id" = back || test -z "$label" ||
       [[ "$label" == *[$'\t\r\n']* || "$label" =~ [[:cntrl:]] ]] ||
       [[ -v labels[$id] ]]; then
      printf 'Candidate catalogue is malformed; no update started.\n' >&2
      return 1
    fi
    labels[$id]=$label
    items+=("$id" "$label")
  done <<< "$snapshot"
  if choice=$(dialog --stdout --title ' Choose an update ' --default-item back --menu \
    'Choose a locally approved candidate. Preparation preserves saved installation settings and leaves the running desktop in place. A restart is required.' \
    20 76 8 "${items[@]}" back 'Keep the current system'); then :
  else status=$?; case "$status" in 1|255) return 0 ;; *) return "$status" ;; esac; fi
  if test "$choice" = back; then return 0; fi
  # Never pass a response from dialog directly to the privileged backend.
  for id in "${!labels[@]}"; do
    if test "$choice" = "$id"; then found=yes; label_selected=${labels[$id]}; break; fi
  done
  if test "$found" != yes; then return 2; fi
  if confirm_update "Prepare $label_selected for the next boot?\n\nSaved installation settings are retained. Dependencies may be downloaded or built. The running system stays in place; boot success is checked after restart."; then :
  else status=$?; if test "$status" -eq 1; then return 0; else return "$status"; fi; fi
  update_result prepare "$choice"
}

recover_update() {
  local status
  if confirm_update 'Recover the incomplete update transaction?\n\nThis restores the saved system selection for that transaction. It does not restore personal files. Read Update status first if you are unsure.'; then :
  else status=$?; if test "$status" -eq 1; then return 0; else return "$status"; fi; fi
  update_result recover-update
}

menu() {
  local choice status summary
  if choice=$(dialog --stdout --title ' Sleepy system ' --menu \
    'Manage this installation. Apply saved settings does not download a new Sleepy version.' \
    22 76 8 \
    status 'Current and booted system' \
    generations 'List recovery generations' \
    rebuild 'Apply the configuration saved in /etc/nixos' \
    rollback 'Return to the previous system generation' \
    update 'Prepare an approved update for the next boot' \
    update-status 'Read update status' \
    recover-update 'Recover an incomplete update'); then
    :
  else
    status=$?
    case "$status" in 1|255) return 0 ;; *) return "$status" ;; esac
  fi
  case "$choice" in
    update) choose_update ;;
    update-status) update_result update-status ;;
    recover-update) recover_update ;;
    status)
      summary=$(system_status brief)
      dialog --title ' System status ' --msgbox "$summary" 18 76
      ;;
    generations)
      summary=$(list_generations) || return $?
      dialog --title ' Recovery generations ' --msgbox "$summary" 22 76
      ;;
    rebuild|rollback)
      if test "$choice" = rollback; then
        summary='Switch to the previous system generation now?\n\nThis changes system software and settings. It does not restore deleted files or undo personal application data changes. Keep important files backed up.'
      else
        summary='Apply the configuration already saved in /etc/nixos?\n\nThis may build or download its dependencies and restart system services. It does not select a new Sleepy release or change channels.'
      fi
      if dialog --title ' Confirm system change ' --defaultno --yesno "$summary" 15 76; then
        :
      else
        status=$?
        case "$status" in 1|255) return 0 ;; *) return "$status" ;; esac
      fi
      # Return the terminal to normal output for real sudo authentication and
      # Nix progress. No password is collected by dialog or piped into sudo.
      dialog --clear
      if run_saved "$choice"; then status=0; else status=$?; fi
      if test "$status" -eq 0; then summary='Completed. The command output above contains the diagnostic log path.'
      else summary="The operation failed (exit $status). Read the diagnostic log shown above. An earlier system generation can also be selected in the boot menu."; fi
      dialog --title ' System operation result ' --msgbox "$summary" 12 76 || true
      return "$status"
      ;;
    *) printf 'Unknown menu operation.\n' >&2; return 2 ;;
  esac
}

if test "$#" -gt 1; then usage >&2; exit 2; fi
case "${1:-menu}" in
  menu) menu ;;
  status) system_status ;;
  generations) list_generations ;;
  rebuild|rollback) run_saved "$1" ;;
  update) choose_update ;;
  update-status) run_saved update-status ;;
  recover-update) recover_update ;;
  help|--help|-h) usage ;;
  *) usage >&2; exit 2 ;;
esac
