#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 1; then
  printf 'usage: %s <flake.nix>\n' "${0##*/}" >&2
  exit 2
fi

flake=$1

awk '
  BEGIN {
    in_block_comment = 0
    found_token = 0
  }

  {
    line = $0 "\n"
    for (cursor = 1; cursor <= length(line); cursor += 1) {
      character = substr(line, cursor, 1)
      following = substr(line, cursor + 1, 1)

      if (in_block_comment) {
        if (character == "*" && following == "/") {
          in_block_comment = 0
          cursor += 1
        }
        continue
      }

      if (character == "#") {
        break
      }

      if (character == "/" && following == "*") {
        in_block_comment = 1
        cursor += 1
        continue
      }

      if (character ~ /[[:space:]]/) {
        continue
      }

      found_token = 1
      if (character == "{") {
        exit 0
      }

      printf "flake shape: expected literal top-level attribute set, found %s\n", \
        character > "/dev/stderr"
      exit 1
    }
  }

  END {
    if (!found_token) {
      print "flake shape: no top-level expression found" > "/dev/stderr"
      exit 1
    }
  }
' "$flake"

printf 'flake shape: ok\n'
