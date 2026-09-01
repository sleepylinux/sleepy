#!/usr/bin/env bash
set -euo pipefail

for required_command in awk jq mktemp; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'flake input contract: required command not found: %s\n' \
      "$required_command" >&2
    exit 127
  fi
done

if test "$#" -ne 3; then
  printf 'usage: %s <flake.nix> <reviewed-manifest.json> <baseline-manifest.json>\n' \
    "${0##*/}" >&2
  exit 2
fi

flake=$1
manifest=$2
baseline_manifest=$3
extracted_tsv=$(mktemp /tmp/sleepy-flake-inputs.XXXXXX)
extracted_json=$(mktemp /tmp/sleepy-flake-inputs.XXXXXX.json)
trap 'rm -f -- "$extracted_tsv" "$extracted_json"' EXIT

if ! awk '
  BEGIN {
    in_inputs = 0
    finished_inputs = 0
    current_input = ""
    current_url = ""
    nested_inputs = 0
  }

  {
    trimmed = $0
    sub(/^[[:space:]]*/, "", trimmed)
    sub(/[[:space:]]*$/, "", trimmed)

    if (!in_inputs) {
      if (trimmed == "inputs = {") {
        in_inputs = 1
        next
      }

      if (trimmed ~ /^inputs[[:space:]]*=/) {
        print "flake input contract: inputs must be a direct literal set" > "/dev/stderr"
        exit 1
      }

      next
    }

    if (current_input == "") {
      if (trimmed == "};") {
        finished_inputs = 1
        exit 0
      }

      if (trimmed ~ /^[A-Za-z0-9_-]+[[:space:]]*=[[:space:]]*\{$/) {
        current_input = trimmed
        sub(/[[:space:]]*=.*$/, "", current_input)
        if (seen_input[current_input]) {
          printf "flake input contract: duplicate input block: %s\n", \
            current_input > "/dev/stderr"
          exit 1
        }
        seen_input[current_input] = 1
        current_url = ""
      }

      next
    }

    if (nested_inputs) {
      if (trimmed == "};") {
        nested_inputs = 0
      }
      next
    }

    if (trimmed == "inputs = {") {
      if (current_input == "sleepy-m2-baseline") {
        print "flake input contract: historical root inputs must retain their exact locked graph" > "/dev/stderr"
        exit 1
      }
      nested_inputs = 1
      next
    }

    if (trimmed == "};") {
      if (current_url != "") {
        printf "%s\t%s\n", current_input, current_url
      }
      current_input = ""
      current_url = ""
      next
    }

    if (current_input == "sleepy-m2-baseline" && trimmed ~ /^inputs\./) {
      print "flake input contract: historical root inputs must retain their exact locked graph" > "/dev/stderr"
      exit 1
    }

    if (trimmed ~ /^url[[:space:]]*=[[:space:]]*"[^"]+";$/) {
      if (current_url != "") {
        printf "flake input contract: duplicate URL for input: %s\n", \
          current_input > "/dev/stderr"
        exit 1
      }
      current_url = trimmed
      sub(/^url[[:space:]]*=[[:space:]]*"/, "", current_url)
      sub(/";$/, "", current_url)
    }
  }

  END {
    if (!in_inputs || !finished_inputs) {
      print "flake input contract: complete literal inputs set not found" > "/dev/stderr"
      exit 1
    }
  }
' "$flake" >"$extracted_tsv"; then
  exit 1
fi

jq -Rn '
  reduce (inputs | split("\t")) as $input ({};
    .[$input[0]] = $input[1]
  )
' <"$extracted_tsv" >"$extracted_json"

if ! jq -e --slurpfile actual "$extracted_json" '
  .inputs as $reviewed |
  all($reviewed | keys[];
    . as $name |
    $actual[0][$name] == $reviewed[$name].url
  )
' "$manifest" >/dev/null; then
  printf 'flake input contract: component URL literals drift from reviewed manifest\n' >&2
  exit 1
fi

if ! jq -e --slurpfile actual "$extracted_json" '
  .root.url as $expected |
  $actual[0]["sleepy-m2-baseline"] == $expected
' "$baseline_manifest" >/dev/null; then
  printf 'flake input contract: historical root URL drifts from baseline manifest\n' >&2
  exit 1
fi

printf 'flake input contract: ok\n'
