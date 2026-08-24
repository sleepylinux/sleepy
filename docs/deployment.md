# Deploying the Sleepy desktop

## Desktop Milestone 1 candidate gate

The external desktop slice is not deployable until its generated lock and VM
acceptance are recorded. Its reviewed immutable inputs are:

```text
sleepy-sdk      2edbe8310eee69c40e4f75924da67a57942bd1c3
sleepy-session  bf7a23081fe9f9bf83c9f5668e45e91faf943bd1
sleepy-artwork  0dd59cc9d8a77700f7a415997e3dcde396f55e99
sleepy-desktop  f76108510e000b0cb7a758d6992d922e24d8a802
```

On a Nix-enabled clean checkout, generate the missing lock entries and verify
that Nix selected those exact revisions. Do not copy or hand-edit lock nodes
from another checkout:

```bash
nix flake lock
bash checks/component-lock.sh components/desktop-m1.json flake.lock
git diff --check
git diff -- flake.lock
sha256sum flake.lock
```

Commit the generated lock, start again from a clean checkout at that exact
commit, and run:

```bash
bash checks/source-clean-test.sh
bash checks/quickshell-contract-test.sh
bash checks/component-contract-test.sh
bash checks/component-lock-test.sh
bash checks/flake-shape-test.sh
bash checks/flake-input-contract-test.sh
bash checks/license-contract-test.sh
bash checks/component-lock.sh components/desktop-m1.json flake.lock
nix flake check -L --no-write-lock-file
nix build .#sleepy-contract .#sleepy-session \
  .#sleepy-session-user-unit .#sleepy-artwork \
  .#sleepy-shell .#sleepy-settings-preview --no-link -L
nix build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel \
  --no-link --no-write-lock-file --print-out-paths -L
nix build '.#homeConfigurations."lazy@sleepy-vm".activationPackage' \
  --no-link --no-write-lock-file -L
```

Before VM activation, record hashes and metadata for any existing settings and
preset documents under their effective XDG roots. Run `dry-activate`, then
`test`; stop if either document changes. In the graphical session verify:

```bash
systemctl --user show sleepy-session.service \
  -p ActiveState -p SubState -p PartOf -p ExecStart
systemctl --user is-active graphical-session.target quickshell.service

contract_file=$(mktemp)
sleepyctl settings show >"$contract_file"
sleepy-contract validate settings "$contract_file"
rm -- "$contract_file"
```

Confirm the left rail, quick-settings drawer, logical lunar mark, and settings
preview render from the external packages. Only then may the permanent switch
procedure below be used and the exact root commit, generated lock SHA-256,
toplevel, state hashes, and visual results be added to the acceptance record.

The in-tree shell and branding derivations are intentionally retained until
this gate passes. They are fallback/parity evidence, not the configured package
owners. Removing them before one-candidate Nix and VM acceptance is prohibited.

## Deployment boundary

Deploy only a clean, committed public tree. Do not copy `.git`, `.superpowers`,
`.worktrees`, `local`, `secrets`, result paths, outputs, private keys, or other
workstation state into the guest.

The accepted deployment is commit
`d9036c1c957a685d789449a42e334a6183b72eac`. Its `git archive` SHA-256 is:

```text
c5c2f90227d63b81184d53842dd88ee94a1d79c1583cbb0f187ae72fa692e186
```

The deployed NixOS toplevel is:

```text
/nix/store/lfyl6fraa4nb404vcdrb8inxk2f13hpx-nixos-system-sleepy-vm-26.11.20260822.2c423e0
```

`sleepy-vm` retains OpenSSH only through its VM-specific host module. The
maintenance channel used for acceptance was a localhost-only host forward to
guest SSH; it was not exposed on a non-loopback host address. Never put a
maintenance private key in the repository or deployment archive.

## Build before activation

Start from a clean commit and create the transfer artifact with `git archive`:

```bash
(
  set -euo pipefail

  archive=/tmp/sleepy-public.tar
  if test -e "$archive" || test -L "$archive"; then
    printf 'refusing to replace archive path: %s\n' "$archive" >&2
    exit 1
  fi

  if ! dirty=$(git status --porcelain=v1 --untracked-files=all); then
    printf 'cannot inspect repository state\n' >&2
    exit 1
  fi
  if test -n "$dirty"; then
    printf 'refusing to archive a dirty repository:\n%s\n' "$dirty" >&2
    exit 1
  fi

  git archive --format=tar --output="$archive" HEAD
  sha256sum "$archive"
  tar -tf "$archive"
)
```

The strict subshell is the archive gate. A tracked or untracked change exits
before `git archive`; do not rerun only the later archive commands after a
failure.

Extract the archive into a new user-readable guest directory under `/tmp`.
Before using `sudo` or changing `/etc/sleepy`, run the source guard with tools
from the locked nixpkgs input, then run the complete flake check and explicit
toplevel build:

```bash
nix --extra-experimental-features 'nix-command flakes' \
  shell --inputs-from "$source" nixpkgs#ripgrep nixpkgs#git \
  --command bash "$source/checks/source-clean.sh" "$source"

cd "$source"
nix --extra-experimental-features 'nix-command flakes' \
  flake check -L --no-write-lock-file
nix --extra-experimental-features 'nix-command flakes' \
  build .#nixosConfigurations.sleepy-vm.config.system.build.toplevel \
  --no-link --no-write-lock-file --print-out-paths -L
```

The accepted run ended with `all checks passed!`. Nix also emitted the known,
non-fatal warning `unknown flake output 'homeManagerModules'`.

Record `/run/current-system`, `/nix/var/nix/profiles/system`, every system
generation link, and hashes/status for user-owned acceptance files before
activation. Record credential-bearing files only as metadata and hashes; never
copy or print their contents.

Treat the settings file and acceptance sentinel as two independent state
items. Determine each origin before creating anything; accept only a regular,
non-symlink file when the path already exists. Create a fixture only when its
own path is absent, and keep origin, metadata, and SHA-256 evidence in a private
mode-0700 directory. Do not retain either file's contents in evidence:

```bash
#!/usr/bin/env bash
set -euo pipefail

evidence="$(mktemp -d)"
chmod 0700 "$evidence"

prepare_acceptance_file() {
  local label="$1"
  local path="$2"
  local fixture="$3"
  local origin

  if test -L "$path"; then
    printf 'refusing symlink acceptance path: %s\n' "$path" >&2
    return 1
  fi

  if test -e "$path"; then
    if ! test -f "$path"; then
      printf 'refusing non-regular acceptance path: %s\n' "$path" >&2
      return 1
    fi
    origin=existing
  else
    if ! mkdir -p "$(dirname "$path")"; then
      printf 'cannot create acceptance parent: %s\n' "$path" >&2
      return 1
    fi
    if ! (set -o noclobber; printf '%s\n' "$fixture" >"$path"); then
      printf 'acceptance path appeared before fixture creation: %s\n' \
        "$path" >&2
      return 1
    fi
    if test -L "$path" || ! test -f "$path"; then
      printf 'created acceptance path is not a regular file: %s\n' \
        "$path" >&2
      return 1
    fi
    origin=created
  fi

  if test -L "$path" || ! test -f "$path"; then
    printf 'acceptance path changed before evidence capture: %s\n' \
      "$path" >&2
    return 1
  fi

  if ! printf '%s\n' "$origin" >"$evidence/$label.origin"; then
    printf 'cannot record acceptance origin: %s\n' "$label" >&2
    return 1
  fi
  if ! stat -c \
    'device=%d inode=%i type=%F uid=%u gid=%g mode=%f size=%s' "$path" \
    >"$evidence/$label.before.metadata"; then
    printf 'cannot record acceptance metadata: %s\n' "$path" >&2
    return 1
  fi
  if ! sha256sum "$path" | cut -d' ' -f1 \
    >"$evidence/$label.before.sha256"; then
    printf 'cannot record acceptance checksum: %s\n' "$path" >&2
    return 1
  fi
}

prepare_acceptance_file settings \
  "$HOME/.config/sleepy/settings.json" '{"schemaVersion":1}'
prepare_acceptance_file sentinel \
  "$HOME/.local/share/sleepy-acceptance-sentinel" \
  'Sleepy acceptance state.'
```

After activation, compare each file's current hash and metadata with its own
record. Delete a path only when its recorded origin is `created`, and only
after its checksum and metadata still match. Retain every `existing` path:

```bash
verify_acceptance_file() {
  local label="$1"
  local path="$2"
  local origin

  if test -L "$path" || ! test -f "$path"; then
    printf 'acceptance path was removed or replaced: %s\n' "$path" >&2
    return 1
  fi

  if ! stat -c \
    'device=%d inode=%i type=%F uid=%u gid=%g mode=%f size=%s' "$path" \
    >"$evidence/$label.after.metadata"; then
    printf 'cannot record post-state metadata: %s\n' "$path" >&2
    return 1
  fi
  if ! sha256sum "$path" | cut -d' ' -f1 \
    >"$evidence/$label.after.sha256"; then
    printf 'cannot record post-state checksum: %s\n' "$path" >&2
    return 1
  fi

  if ! cmp -s "$evidence/$label.before.metadata" \
    "$evidence/$label.after.metadata"; then
    printf 'acceptance metadata changed; retaining path: %s\n' "$path" >&2
    return 1
  fi
  if ! cmp -s "$evidence/$label.before.sha256" \
    "$evidence/$label.after.sha256"; then
    printf 'acceptance content changed; retaining path: %s\n' "$path" >&2
    return 1
  fi

  if ! IFS= read -r origin <"$evidence/$label.origin"; then
    printf 'cannot read acceptance origin: %s\n' "$label" >&2
    return 1
  fi

  case "$origin" in
    existing)
      return 0
      ;;
    created)
      ;;
    *)
      printf 'invalid acceptance origin for %s: %s\n' "$label" "$origin" >&2
      return 1
      ;;
  esac

  # Revalidate immediately before cleanup. Every mismatch returns above or
  # here, so removal is unreachable for a changed or replaced fixture.
  if test -L "$path" || ! test -f "$path"; then
    printf 'created fixture was removed or replaced; retaining path: %s\n' \
      "$path" >&2
    return 1
  fi
  if ! stat -c \
    'device=%d inode=%i type=%F uid=%u gid=%g mode=%f size=%s' "$path" \
    >"$evidence/$label.cleanup.metadata"; then
    printf 'cannot record cleanup metadata; retaining path: %s\n' \
      "$path" >&2
    return 1
  fi
  if ! sha256sum "$path" | cut -d' ' -f1 \
    >"$evidence/$label.cleanup.sha256"; then
    printf 'cannot record cleanup checksum; retaining path: %s\n' \
      "$path" >&2
    return 1
  fi
  if ! cmp -s "$evidence/$label.before.metadata" \
    "$evidence/$label.cleanup.metadata"; then
    printf 'created fixture metadata changed; retaining path: %s\n' \
      "$path" >&2
    return 1
  fi
  if ! cmp -s "$evidence/$label.before.sha256" \
    "$evidence/$label.cleanup.sha256"; then
    printf 'created fixture content changed; retaining path: %s\n' \
      "$path" >&2
    return 1
  fi

  if ! rm -- "$path"; then
    printf 'created fixture cleanup failed: %s\n' "$path" >&2
    return 1
  fi
  if test -e "$path" || test -L "$path"; then
    printf 'created fixture cleanup did not remove path: %s\n' "$path" >&2
    return 1
  fi
}

verify_acceptance_file settings "$HOME/.config/sleepy/settings.json"
verify_acceptance_file sentinel \
  "$HOME/.local/share/sleepy-acceptance-sentinel"
```

Run preparation and verification from the same dedicated strict Bash session,
keeping `evidence` private for the whole acceptance run. Any nonzero return is
a stop condition: investigate it without deleting or replacing the reported
path. The `existing` branch returns before cleanup, and each `created` path is
validated independently before its own removal.

## Reversible activation and permanent switch

Dry-activate the prebuilt candidate, then test it, before changing the boot
profile. Use explicit failure branches so `test` is structurally unreachable
when `dry-activate` fails; do not depend on `set -e` or an `&&` context.

```bash
if ! sudo /run/current-system/sw/bin/nixos-rebuild dry-activate \
  --flake "$source#sleepy-vm"; then
  printf 'dry activation failed; refusing test activation\n' >&2
  exit 1
fi
if ! sudo /run/current-system/sw/bin/nixos-rebuild test \
  --flake "$source#sleepy-vm"; then
  printf 'test activation failed; refusing permanent switch\n' >&2
  exit 1
fi
```

Inspect the dry-activation result for an unmanaged-file overwrite, Home
Manager collision, or any other activation error. Stop before `test` if one is
reported; adopt or back up a known collision explicitly rather than forcing an
overwrite.

After `test`, verify SSH reconnects, `sshd.service` remains active, user hashes
match, Home Manager links resolve into the Nix store, and the graphical
acceptance checklist passes. Do not use `switch` before that gate.

For the permanent deployment, extract the already verified archive into a new
root-owned staging directory on the `/etc` filesystem. Preserve the existing
tree under a new, unused name, rename the staging directory to `/etc/sleepy`,
then switch:

```bash
sudo /run/current-system/sw/bin/nixos-rebuild switch \
  --flake /etc/sleepy#sleepy-vm
```

Never overwrite a source backup. The accepted deployment retained both earlier
public copies:

```text
/etc/sleepy.pre-d903c1-20260823T201338Z
/etc/sleepy.previous-20260823T183905Z
```

On 2026-08-23 the switch created system generation 5 and retained generations
1 through 4. No generation deletion or garbage collection was performed.

## Interactive authorization

Passwordless `sudo` is intentionally unavailable. Run privileged deployment
commands in a visible guest terminal and authenticate through PAM. A graphical
`pkexec` attempt did not produce a usable prompt in this VM and must not be used
as an authentication bypass.

The configured remote login shell is Fish. For multi-line maintenance scripts,
explicitly invoke Bash instead of sending POSIX shell syntax to the default
remote shell:

```bash
ssh -p 2222 -i <maintenance-key> lazy@127.0.0.1 \
  '/run/current-system/sw/bin/bash -s' < maintenance-script.sh
```

Keep `IdentitiesOnly=yes`, host-key checking, and the localhost-only forwarding
boundary in the actual SSH configuration.

## VM-specific Ghostty behavior

The integrated `sleepy-vm` profile installs a Ghostty wrapper that sets exactly
`LIBGL_ALWAYS_SOFTWARE=1` for Ghostty and its children. This selects llvmpipe
OpenGL 4.6 because the VM's accelerated virgl renderer exposes OpenGL 4.2 and
Ghostty 1.3.1 requires OpenGL 4.3. The variable is not global or session-wide.

Fuzzel's terminal command follows the same final wrapped package. Standalone
Home Manager continues to use the normal pinned Ghostty package.
