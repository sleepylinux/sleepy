# Snug command guide and contract

Snug is SleepyLinux's CLI for Nix. This file is the durable reference for its
behavior: when changing syntax, update this guide, `snug --help` and the tests
together. Short flags and long forms perform the same operation.

## Main commands

| Short form | Long form | Result |
| --- | --- | --- |
| `snug -i vim` | `snug --install vim` | Install Vim for the current user |
| `snug -it vim` | `snug --install --temporary vim` | Open a temporary environment with Vim |
| `snug -r vim` | `snug --remove vim` | Remove a package installed in the Snug profile |
| `snug -s editor` | `snug --search editor` | Search for packages in nixpkgs |
| `snug -l` | `snug --list` | List personal packages |
| `snug -u` | `snug --update` | Update all personal packages |
| `snug -b` | `snug --rollback` | Restore the previous personal package generation |
| `snug -x hello` | `snug --run hello` | Run a program without installing it permanently |
| `snug -e git ripgrep` | `snug --shell git ripgrep` | Open a temporary environment with several tools |
| `snug -d` | `snug --dev` | Enter the current project's development environment |
| `snug -u --system` | `snug --update --system` | Update rolling SleepyLinux |
| `snug -b --system` | `snug --rollback --system` | Roll back the system generation |
| `snug --doctor` | `snug doctor` | Check Nix availability and session paths |
| `snug -h` | `snug --help` | Show help |

Subcommands such as `snug install`, `snug remove`, `snug update` and `snug dev`
are also available. Request command-specific help with `snug install --help`
or `snug dev --help`. `snug --version` shows Snug's own version.
Use `snug -l --json` for machine-readable package information and
`snug generations` for personal profile history.

## Permanent and temporary installation

```sh
snug -i vim git ripgrep
snug -it nodejs
# Node is available in the new shell. Run exit to leave the environment.
snug -it git -- git --version
snug -x hello -- --greeting 'Hello!'
```

`-it` means `-i -t`; `-ti` and `install -t` are also supported.
A temporary environment does not add packages to the permanent profile.
After leaving it, its packages are no longer added to your PATH by that
environment. Downloaded objects remain cached in the Nix store: temporary
installation does not promise to remove their files from disk immediately.

Packages install without sudo into a separate profile at
`${XDG_STATE_HOME:-$HOME/.local/state}/snug/profile`. Sleepy adds its `bin`
directory to PATH and its `share` directory to XDG_DATA_DIRS so applications
appear in the launcher. Log out and back in after first enabling this integration.

Packages selected in the installer belong to the OS configuration. `snug -r`
manages the personal profile; it does not remove system or Home Manager packages.
To change the installation's package selection, edit
`/etc/nixos/configuration.nix` and rebuild the OS. `snug -u --system` also applies
that configuration during an update. Do not mix `nix-env` and `nix profile`
in the same profile.

The personal package source is `github:NixOS/nixpkgs/nixos-unstable`. This is a
rolling source: initial installation resolves the currently available version,
and an update resolves a newer source revision. The profile retains generations
for rollback. Snug does not automatically collect garbage or delete previous
generations.

## Unfree packages

Some packages, including Steam, have licenses that Nixpkgs classifies as unfree.
Opt in explicitly for the personal operation:

```sh
snug -i --unfree steam
snug -it --unfree steam
snug -x --unfree steam
snug -e --unfree steam -- steam --version
snug -s --unfree steam
snug -u --unfree
```

`--unfree` is supported by install (including temporary installation), run,
shell, search and personal update. Put it before the package name when using
`-x`, because arguments after that name belong to the application. Arguments
after `--` always belong to the launched command.

The flag passes `--impure` to Nix and sets `NIXPKGS_ALLOW_UNFREE=1` only in that
command's subprocess environment. This allows Nixpkgs to read the opt-in; it
also enables Nix's normal impure evaluation behavior, including reading other
inherited environment settings. Snug does not write a global licensing setting
or change the parent shell. Ordinary commands retain their existing defaults.
Use `--unfree` again when updating a profile containing unfree packages.

`--unfree --system` is rejected: system package licensing belongs in the
root-owned host configuration, such as `nixpkgs.config.allowUnfree = true;`.
Allowing a license does not guarantee that an application supports the machine's
hardware or that its download/build will succeed; failures retain their exit
status.

## Development environments

```sh
snug -d init python my-project
cd my-project
snug -d
snug -d -- python --version
snug -d update
```

Available presets are `python` (Python and uv), `node` (Node.js and npm), and
`rust` (Rust, Cargo, rustfmt, clippy and pkg-config). `init` creates `flake.nix`
and a real `flake.lock` generated by Nix. It does not overwrite existing files.
If downloading or generating the lock fails, existing project files remain
untouched.

Save both files in Git. Entering an environment normally does not request a
dependency update; `snug -d update` explicitly updates dependencies. You can edit
`devShells` in the flake and use existing project flakes. Python, npm and Cargo
dependencies still belong to the project and are managed by their respective
tools.

## All other Nix capabilities

```sh
snug nix flake show
snug nix build .#my-package
snug nix eval --expr '1 + 2'
snug nix develop .#other-shell
snug nix repl
snug nix store info
snug nix --help
```

`snug nix …` passes arguments directly to Nix, including Nix's own flags.
`snug --nix …` is an equivalent form. Snug enables the `nix-command` and `flakes`
experimental features when invoking Nix. This provides access to the full `nix`
command interface rather than implementing those functions separately. Standard
Nix paths, permissions and behavior apply in this mode; Snug does not select its
personal profile automatically. Check the target profile when modifying it
directly. Legacy standalone commands such as `nix-env` remain separate programs.

## Rolling system updates

```sh
snug -u --system
snug -b --system
```

The installer creates a root-owned `/etc/snug/system.json`:

```json
{
  "flake": "/etc/nixos",
  "host": "sleepy",
  "input": "sleepy",
  "source": "github:sleepylinux/sleepy"
}
```

The `host` field names an entry in `nixosConfigurations`. The host configuration
and local hardware and user settings live in `/etc/nixos`. A rolling update
advances the `sleepy` input from main together with its pinned components,
keeping the dependency graph selected by Sleepy intact.

System operations require normal sudo authentication. A candidate is prepared
separately and built before switching; the previous generation is retained.
Download or build failures must not change the boot profile. Activation failure
returns an error even if the previous configuration was successfully restored.
Keep previous generations until you have checked the new version after rebooting.

If the candidate builds the same system already selected in the system profile,
Snug reports that no configuration changed. It preserves the host lock and
rollback receipt, even if the candidate lock resolved a newer source revision.
A later update can retry that source without changing the existing generation's
rollback history. If the host lock was deleted or its directory moved, OS
rollback still proceeds without recreating the missing lock or directory.

OS rollback does not restore arbitrary user files, application databases or
uncommitted configuration changes. For kernel problems, select a previous
generation in the bootloader. See the [recovery guide](recovery.md).

## Errors and diagnostics

- `snug --doctor` reports the profile, session paths and whether a system
  configuration exists.
- Nix failures retain a nonzero exit status. A failed build does not produce
  a successful-installation message.
- Only one operation can modify a personal profile at a time. A concurrent
  operation exits with an explanation; do not remove the lock file while
  another operation is running.
- Nix may require network access or a local build if no binary cache is available.
- Free and proprietary packages follow Nix's licensing policy. Use the explicit
  `--unfree` opt-in for personal packages when required; Snug does not report a
  licensing refusal as success.

## Developer verification

```sh
python3 checks/snug-test.py
python3 checks/snug-system-test.py
nix build .#snug .#checks.x86_64-linux.snug
```

External-command tests use isolated profiles or stubs that record invocations.
CLI checks do not replace VM tests of installation, reboot and system rollback.

## Desktop launcher integration

Sleepy creates `$XDG_DATA_HOME/snug/applications` before the desktop starts and
adds its parent to XDG_DATA_DIRS. After each personal profile mutation, Snug
projects the profile's `.desktop` entries into that stable directory without
changing their application IDs. This lets the launcher notice the first GUI
installation, even if the Nix profile did not exist at login. The profile's
share directory remains available for icons and other application resources.

Snug never replaces unrelated files in the projection directory. If refreshing
fails after Nix succeeds, the error explicitly says that packages changed;
resolve the directory conflict and run `snug refresh` (or `snug --refresh`).
The desktop shell is not restarted as a side effect of package installation.

## Publishing rolling updates

The default OS source is `github:sleepylinux/sleepy`. Local worktree changes and
an ISO built from them are not automatically published to that repository.
Release maintainers must publish the tested source and component locks before
installed machines can retrieve those changes through `snug -u --system`.
An older remote revision without the required host API cannot build the new
host configuration; Snug reports the build failure and retains the active OS.

The disposable acceptance test exercises real Nix builds, activation and
rollback against a local candidate fixture. It does not claim that unpublished
changes have already passed an unmodified public GitHub update.
