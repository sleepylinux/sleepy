#!/usr/bin/env bash
set -euo pipefail

if test "$#" -ne 1; then
  printf 'usage: %s <baseline-manifest.json>\n' "${0##*/}" >&2
  exit 2
fi

expected=9826d89721fc4b98490f66fe1ff11f05dde1337013f4c1e49897f4214d33e878
actual=$(sha256sum "$1" | cut -d' ' -f1)
if test "$actual" != "$expected"; then
  printf 'baseline provenance: immutable M1 manifest hash mismatch\n' >&2
  exit 1
fi

printf 'baseline provenance: ok\n'
