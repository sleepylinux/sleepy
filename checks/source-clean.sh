#!/usr/bin/env bash
set -euo pipefail

if ! command -v rg >/dev/null 2>&1; then
  printf 'source-clean: required command not found: rg\n' >&2
  exit 127
fi

repo_root=${1:-$(git rev-parse --show-toplevel)}
repo_root=$(cd "$repo_root" && pwd -P)
manifest=$(mktemp /tmp/sleepy-source-manifest.XXXXXX)
trap 'rm -f -- "$manifest"' EXIT

resolve_symlink_target() {
  local relative_path=$1
  local link_directory=
  local link_target
  local component
  local candidate
  local nested_target
  local resolved_path
  local last_index
  local symlink_depth=0
  local index=0
  local -a pending
  local -a resolved=()
  local -a nested

  link_target=$(readlink "$repo_root/$relative_path")
  case "$link_target" in
    /* ) return 1 ;;
  esac

  case "$relative_path" in
    */* ) link_directory=${relative_path%/*} ;;
  esac
  IFS=/ read -r -a pending <<<"${link_directory:+$link_directory/}$link_target"

  while [ "$index" -lt "${#pending[@]}" ]; do
    component=${pending[$index]}
    index=$((index + 1))

    case "$component" in
      '' | . ) continue ;;
      .. )
        if [ "${#resolved[@]}" -eq 0 ]; then
          return 1
        fi
        last_index=$((${#resolved[@]} - 1))
        unset "resolved[$last_index]"
        continue
        ;;
    esac

    resolved+=("$component")
    resolved_path=$(IFS=/; printf '%s' "${resolved[*]}")
    candidate="$repo_root/$resolved_path"

    if [ -L "$candidate" ]; then
      symlink_depth=$((symlink_depth + 1))
      if [ "$symlink_depth" -gt 64 ]; then
        return 1
      fi

      nested_target=$(readlink "$candidate")
      case "$nested_target" in
        /* ) return 1 ;;
      esac

      last_index=$((${#resolved[@]} - 1))
      unset "resolved[$last_index]"
      IFS=/ read -r -a nested <<<"$nested_target"
      pending=("${nested[@]}" "${pending[@]:$index}")
      index=0
    fi
  done

  (IFS=/; printf '%s\n' "${resolved[*]}")
}

if git -C "$repo_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$repo_root" ls-files -z >"$manifest"
else
  find "$repo_root" \( -type f -o -type l \) -printf '%P\0' >"$manifest"
fi

failed=0
while IFS= read -r -d '' relative_path; do
  source_path="$repo_root/$relative_path"

  case "$relative_path" in
    local | local/* | secrets | secrets/* | outputs | outputs/* | result | result-* | results | results/* )
      printf 'forbidden tracked source path: %s\n' "$relative_path" >&2
      failed=1
      ;;
  esac

  case "$relative_path" in
    *.pem | *.key | id_dsa | id_ecdsa | id_ed25519 | id_rsa )
      printf 'private-key-shaped tracked source path: %s\n' "$relative_path" >&2
      failed=1
      ;;
  esac

  if [ -L "$source_path" ]; then
    if ! resolved_target=$(resolve_symlink_target "$relative_path"); then
      printf 'tracked source symlink escapes the repository or cannot be resolved safely: %s\n' \
        "$relative_path" >&2
      failed=1
      continue
    fi

    case "$resolved_target" in
      local | local/* | secrets | secrets/* | outputs | outputs/* | result | result-* | results | results/* )
        printf 'tracked source symlink resolves to a forbidden path: %s -> %s\n' \
          "$relative_path" "$resolved_target" >&2
        failed=1
        ;;
    esac
    continue
  fi

  if [ ! -f "$source_path" ]; then
    continue
  fi

  if rg -I -q -- \
    '-----BEGIN ([A-Z0-9]+ )?PRIVATE[[:space:]]+KEY([[:space:]]+BLOCK)?-----' "$source_path"; then
    printf 'private key material found in public source: %s\n' "$relative_path" >&2
    failed=1
  fi

  case "$relative_path" in
    *.nix )
      if rg -n -- \
        "([.][.]/|[.]/)(local|secrets)(/|[.]nix|[\"'])" "$source_path"; then
        printf 'Nix source depends on a forbidden local or secret path: %s\n' \
          "$relative_path" >&2
        failed=1
      fi
      ;;
    .github/workflows/*.yml | .github/workflows/*.yaml )
      if rg -n -- 'actions/upload-artifact@' "$source_path"; then
        printf 'CI must not upload build artifacts: %s\n' "$relative_path" >&2
        failed=1
      fi
      ;;
  esac
done <"$manifest"

if [ "$failed" -ne 0 ]; then
  exit 1
fi

printf 'source-clean: ok\n'
