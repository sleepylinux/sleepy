# Installed-disk recovery snapshot 2537643

Fresh TUI installation, 40 gates and two real-password disk-only boots passed.
The second boot followed deliberate removal of ESP boot entries and offline TUI
repair. Inspection/cancel preserved GPT and full partition hashes; settings,
configuration, keyring and the saved PNG survived. No optional profiles selected;
US/Russian desktop layout and the explicitly signed local cache were used.

This does **not** establish candidate-update acceptance. A separate update run
booted this source but reproduced a lost lock request during session-daemon
reconnection. That failed run remains failed; a corrected replacement is planned.
The machine-readable manifest records exact image/runner revisions and checksum.
