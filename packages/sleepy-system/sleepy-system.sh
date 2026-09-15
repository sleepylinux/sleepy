# Packaged with fixed executable/theme paths by the NixOS module.
set -euo pipefail
export DIALOGRC=@dialogrc@

usage() {
  printf '%s\n' 'sleepy-system [menu | status | generations | rebuild | rollback]' \
    'rebuild applies the configuration already saved in /etc/nixos; it does not download a new Sleepy version.'
}

system_status() {
  local label path resolved
  for label in 'Current system' 'Booted system' 'Selected system profile'; do
    case "$label" in
      'Current system') path=/run/current-system ;;
      'Booted system') path=/run/booted-system ;;
      *) path=/nix/var/nix/profiles/system ;;
    esac
    resolved=$(readlink -e "$path") || resolved='unavailable'
    if test "${1:-full}" = brief; then
      case "$resolved" in
        /nix/store/*) resolved=${resolved##*/}; resolved=${resolved#*-} ;;
      esac
    fi
    printf '%s: %s\n' "$label" "${resolved:-unavailable}"
  done
}

run_saved() {
  local operation=$1 log_directory log status
  local -a args pipeline_status
  case "$operation" in
    rebuild) args=(switch --flake /etc/nixos#installed) ;;
    rollback) args=(switch --rollback) ;;
    *) return 2 ;;
  esac
  umask 077
  log_directory="${XDG_STATE_HOME:-$HOME/.local/state}/sleepy/system"
  mkdir -p "$log_directory"
  log=$(mktemp "$log_directory/$operation.XXXXXXXX.log")
  printf '%s\n' "Sleepy: $operation. Administrator authentication may be requested." \
    "Live progress follows. Diagnostics: $log"
  # sudo uses its normal terminal prompt. Only command output is recorded;
  # never read or redirect terminal input, password prompts or credentials.
  set +e
  sudo @rebuild@ "${args[@]}" 2>&1 | tee "$log"
  pipeline_status=("${PIPESTATUS[@]}")
  set -e
  status=${pipeline_status[0]}
  if test "$status" -eq 0; then status=${pipeline_status[1]}; fi
  if test "$status" -eq 0; then
    printf 'Sleepy: %s completed. Diagnostics: %s\n' "$operation" "$log"
  else
    printf 'Sleepy: %s failed (exit %s). Diagnostics: %s\n' "$operation" "$status" "$log" >&2
  fi
  return "$status"
}

menu() {
  local choice status summary
  if choice=$(dialog --stdout --title ' Sleepy system ' --menu \
    'Manage this installation. Apply saved settings does not download a new Sleepy version.' \
    18 76 5 \
    status 'Current and booted system' \
    generations 'List recovery generations' \
    rebuild 'Apply the configuration saved in /etc/nixos' \
    rollback 'Return to the previous system generation'); then
    :
  else
    status=$?
    case "$status" in 1|255) return 0 ;; *) return "$status" ;; esac
  fi
  case "$choice" in
    status)
      summary=$(system_status brief)
      dialog --title ' System status ' --msgbox "$summary" 18 76
      ;;
    generations)
      summary=$(nix-env --list-generations -p /nix/var/nix/profiles/system) || return $?
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
  generations) exec nix-env --list-generations -p /nix/var/nix/profiles/system ;;
  rebuild|rollback) run_saved "$1" ;;
  help|--help|-h) usage ;;
  *) usage >&2; exit 2 ;;
esac
