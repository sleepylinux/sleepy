# Preparing an approved Sleepy update

Open `sleepy-system` in a terminal. Preparing an approved candidate builds it
with your saved installation settings, then selects it for the **next boot**.
Your current desktop keeps running. Reboot when preparation succeeds; keep the
previous generation until you have checked login, networking and applications.

The catalog is initially empty. This alpha does not follow a moving branch or
automatically promote a public channel. A candidate must first be reviewed and
explicitly added by the administrator or distribution maintainer. A source hash
verifies the selected content; it does not establish that the content is safe.

`sleepy-system rebuild` applies saved settings using the source retained by the
running generation. Candidate preparation does not rewrite `/etc/nixos`, its
lock file, the installation's original `sleepy-source`, passwords or personal
files. A rollback therefore restores the previous source for subsequent saved
rebuilds as well as the previous system. Changes you made to saved settings
remain your changes; rollback does not undo edits or recover erased data.

If preparation fails before selection, the current profile remains unchanged.
If selection or boot-entry generation fails, Sleepy attempts to reselect the
captured previous generation and regenerate its boot entries. An interrupted
selection can be retried through the menu's update recovery action. Recovery
refuses an unrelated profile rather than replacing another administrator's work.
Keep `/var/lib/sleepy-update/update.log` for diagnosis; it requires root to read.
Recovery cannot guarantee success after power loss or broken storage. Use the
[boot menu and installer recovery](recovery.md) if the installed system cannot
start. A successfully prepared candidate waits for reboot or explicit rollback;
the incomplete-update recovery action does not silently undo it.

The menu's update status describes the last transaction. `ready` means that a
system was selected for the next boot; check the separately displayed running
system to see whether you have booted it. It is not a certification that the new
desktop or hardware works. Closing the terminal after selection or recovery
has been durably recorded does not reverse the completed operation.

Each attempt uses its own temporary Nix GC root. Completed attempts release
that reference after recording their result; normal system generations retain
the selected systems. Incomplete recovery keeps its reference. Historical status
remains readable after old generations are deliberately removed and garbage
collected, but recovery still requires its previous generation to be retained.

## Administrator catalog

Declare `sleepy.updates.candidates.<id>` in the saved configuration with a display
`version`, an exact 40-character `revision` from `sleepylinux/sleepy`, and its
`nar_hash` in SHA-256 SRI form. Apply the saved configuration to expose the entry.
This is an explicit local approval, not release publication. Do not add an
unreviewed commit merely because its hash can be fetched.

The same structured catalog can be managed as root-owned JSON files in
`/etc/sleepy/candidates/<id>.json`. Each file has exactly these fields:
`schema` (1), `id`, `version`, `revision`, `nar_hash`. IDs are 1–64 lowercase
letters, digits, dots, underscores or hyphens and start with a letter or digit.
The backend rejects writable/untrusted catalog files, arbitrary repository URLs,
moving revisions, hash mismatches and changed approvals. Nix-managed catalog
symlinks must resolve into the immutable store.

For diagnosis, `sleepy-update candidates --json` lists the approved entries,
`sleepy-update source` prints the running generation's source, and
`sudo sleepy-update status` shows the private transaction state. Advanced
operations are `sudo sleepy-update prepare <id>` and `sudo sleepy-update recover`.
They use Nix's existing build, profile and boot mechanisms; no separate package
database is introduced. Legacy generations without source metadata keep the
original saved-flake rebuild behavior.

## Verification status

Implementation and regression checks are in progress. Candidate update VM
acceptance is pending; the existing installation and offline repair evidence
does not by itself verify this update path.
