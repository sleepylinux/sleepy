"""Fixed disposable-guest boot-repair fixture; never used against host devices."""
import base64
import socket
import time
import shlex


def fixture(phase):
    if phase is None:
        return ''
    common = r'''
state=/var/lib/sleepy-alpha/boot-recovery
# Machine only attaches its newly created qcow2 as vda. Refuse any other layout.
test "$(findmnt -no SOURCE /boot)" = /dev/vda1
test "$(findmnt -no FSTYPE /boot)" = vfat
test "$(findmnt -no SOURCE / | cut -d '[' -f 1)" = /dev/vda2
'''
    if phase == 'damage':
        return common + r'''
test ! -e "$state"
install -d -m 0700 "$state"
readlink -f /run/current-system > "$state/system.before"
readlink -f /nix/var/nix/profiles/system > "$state/profile.before"
runuser -u sleepy -- sh -c 'printf "Sleepy boot repair must preserve this file.\n" > "$HOME/boot-recovery-proof.txt"'
sha256sum /home/sleepy/boot-recovery-proof.txt > "$state/userdata.before"
sha256sum /etc/nixos/configuration.nix /etc/nixos/flake.nix /etc/nixos/flake.lock > "$state/config.before"
find /boot/EFI -type f -print0 | sort -z | xargs -0 sha256sum > "$state/efi.before"
test -s "$state/efi.before"
test -d /boot/loader/entries
test -n "$(find /boot/loader/entries -maxdepth 1 -type f -name '*.conf' -print -quit)"
# Deliberately damage only boot-entry configuration on the disposable ESP.
find /boot/loader/entries -maxdepth 1 -type f -name '*.conf' -delete
test -z "$(find /boot/loader/entries -mindepth 1 -maxdepth 1 -print -quit)"
sync
printf 'BOOT_RECOVERY_ESP_ENTRIES_REMOVED_OK\n'
'''
    if phase == 'verify':
        return common + r'''
test "$(readlink -f /run/current-system)" = "$(cat "$state/system.before")"
test "$(readlink -f /nix/var/nix/profiles/system)" = "$(cat "$state/profile.before")"
sha256sum --check "$state/userdata.before"
sha256sum --check "$state/config.before"
# Boot repair may rewrite bootloader binaries, but must restore boot entries.
test -n "$(find /boot/loader/entries -maxdepth 1 -type f -name '*.conf' -print -quit)"
grep -r -F "$(cat "$state/system.before")/init" /boot/loader/entries
printf 'BOOT_RECOVERY_PROFILE_USERDATA_AND_ENTRIES_OK\n'
'''
    raise ValueError('Unknown boot recovery fixture phase')


def recovery_tui(machine, verify_cancel):
    def wait(fragment, name, **kwargs):
        return machine.wait_screen(fragment, name, reject=(
            'Recovery needs attention', 'Boot repair stopped', 'Confirmation did not match'), **kwargs)
    wait('Welcome home', 'recovery-welcome', timeout=300)
    machine.qmp.keys('down')
    machine.qmp.keys('down')
    machine.qmp.keys('ret')
    wait('Recover Sleepy boot', 'recovery-disk')
    machine.qmp.keys('home')  # sole eligible VM disk, independent of safe default
    machine.qmp.keys('ret')
    wait(['Installed Sleepy', 'Current generation:', 'Retained generations:'], 'recovery-inspection')
    # Back is deliberately the default: Enter must not perform a repair.
    machine.qmp.keys('ret')
    wait('Recover Sleepy boot', 'recovery-cancelled')
    verify_cancel()
    machine.qmp.keys('home')
    machine.qmp.keys('ret')
    wait(['Installed Sleepy', 'Current generation:', 'Retained generations:'], 'recovery-inspection-again')
    machine.qmp.keys('up')
    machine.qmp.keys('ret')
    wait('Confirm boot repair', 'recovery-confirmation')
    machine.qmp.text('/dev/vda')
    machine.qmp.keys('ret')
    wait('Boot repair complete', 'recovery-complete', timeout=300)



BUSY_TARGET_PROBE = r'''import json, pathlib, secrets, subprocess
rows = json.loads(subprocess.check_output(['sleepy-install-backend', '--list'], text=True))
disk = next(row for row in rows if row['path'] == '/dev/vda')
assert disk['eligible']
request = dict(disk='/dev/vda', identity=disk['identity'])
mount = pathlib.Path('/run/sleepy-recovery-busy-probe')
mount.mkdir(mode=0o700)
subprocess.run(['mount', '-o', 'ro', '/dev/vda1', str(mount)], check=True)
try:
    mounted = next(row for row in json.loads(subprocess.check_output(
        ['sleepy-install-backend', '--list'], text=True)) if row['path'] == '/dev/vda')
    assert not mounted['eligible'] and 'mounted' in mounted['reason'].lower(), mounted
    install_request = dict(request, confirm_erase='/dev/vda', username='sleepy',
                           password=secrets.token_hex(12), hostname='sleepy',
                           locale='en_US.UTF-8', keyboard='us', timezone='UTC', options={})
    install = subprocess.run(['sleepy-install-backend', '--install'], input=json.dumps(install_request),
                             capture_output=True, text=True, timeout=30)
    events = [json.loads(line) for line in install.stdout.splitlines()]
    assert install.returncode != 0 and events[-1]['stage'] == 'error', install.stdout
    assert 'mounted' in events[-1]['message'].lower(), install.stdout
    assert not any(event['stage'] in ('network', 'preflight', 'partition') for event in events), install.stdout
    print('INSTALL_BUSY_DESCENDANT_REJECTED_OK', flush=True)
    result = subprocess.run(['sleepy-recover-backend', '--inspect'], input=json.dumps(request),
                            capture_output=True, text=True, timeout=30)
    assert result.returncode != 0, 'Recovery accepted a mounted target'
    assert 'mounted' in json.loads(result.stdout)['message'].lower(), result.stdout
finally:
    subprocess.run(['umount', str(mount)], check=True)
    mount.rmdir()
print('RECOVERY_BUSY_TARGET_REJECTED_OK', flush=True)
'''


def repair(machine, iso, serial_line, shell_prompt):
    """Called only after authenticated damage, with the machine shut down."""
    machine.boot('broken-boot')
    # Positive firmware evidence, not merely absence of a login before timeout.
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        text = machine.screen('broken-boot').lower()
        if any(s in text for s in ('no bootable option', 'no boot loader entries found', 'uefi interactive shell',
                                    'reboot into firmware interface', 'boot manager')):
            break
        time.sleep(3)
    else:
        raise RuntimeError('Damaged disk did not show a recognizable no-entry/firmware screen')
    machine.stop()
    machine.boot('recovery', iso)
    machine.qmp.call('stop')
    machine.qmp.call('set_link', name='nic0', up=False)
    machine.qmp.call('cont')
    # Serial is diagnostic only; all inspect/cancel/restore actions use tty1 TUI.
    import pexpect.fdpexpect
    channel = socket.socket(socket.AF_UNIX)
    channel.connect(str(machine.output / 'serial.sock'))
    terminal = pexpect.fdpexpect.fdspawn(channel, encoding='utf-8', codec_errors='replace', timeout=300)
    with (machine.output / 'recovery-serial.log').open('w') as log:
        terminal.logfile_read = log
        try:
            terminal.expect(shell_prompt)
            snapshot = ('set -eu; test "$(lsblk -dn -o TYPE /dev/vda)" = disk; '
                        'test -z "$(lsblk -nr -o MOUNTPOINT /dev/vda | tr -d "[:space:]")"; '
                        'sfdisk --dump /dev/vda > /run/recovery-partitions.before; '
                        'sha256sum /dev/vda1 /dev/vda2 > /run/recovery-blocks.before; '
                        'printf "RECOVERY_BASELINE_%s\\n" OK')
            serial_line(terminal, 'sudo -n sh -c ' + shlex.quote(snapshot), 'RECOVERY_BASELINE_OK')
            # Exercise a real busy descendant through the same structured backend.
            # Mount only the disposable ESP read-only; inspect must reject it.
            encoded = base64.b64encode(BUSY_TARGET_PROBE.encode()).decode()
            probe = ("set -eu; sleepy_python=$(grep -oE '/nix/store/[a-z0-9]+-python3-[^/]+/bin/python3' "
                     "\"$(readlink -f \"$(command -v sleepy-install-backend)\")\" | head -n1); "
                     + "printf %s " + shlex.quote(encoded) + " | base64 -d > /run/recovery-busy.py; "
                     + "\"$sleepy_python\" /run/recovery-busy.py")
            serial_line(terminal, 'sudo -n sh -c ' + shlex.quote(probe), 'RECOVERY_BUSY_TARGET_REJECTED_OK')
            def verify_cancel():
                check = ('set -eu; sfdisk --dump /dev/vda > /run/recovery-partitions.after; '
                         'cmp /run/recovery-partitions.before /run/recovery-partitions.after; '
                         'sha256sum --check /run/recovery-blocks.before; '
                         'test -z "$(lsblk -nr -o MOUNTPOINT /dev/vda | tr -d "[:space:]")"; '
                         'printf "RECOVERY_INSPECT_CANCEL_%s\\n" OK')
                serial_line(terminal, 'sudo -n sh -c ' + shlex.quote(check), 'RECOVERY_INSPECT_CANCEL_OK')
            try:
                recovery_tui(machine, verify_cancel)
            finally:
                # Fixed privileged diagnostics from this disposable guest only.
                # The backend log excludes credentials; retain it before shutdown.
                serial_line(terminal, "sudo -n sh -c 'cat /var/log/sleepy-installer.log; printf \"RECOVERY_LOG_END_%s\\n\" OK'",
                            'RECOVERY_LOG_END_OK', timeout=30)
            # Complete dialog does not auto-reboot. Explicitly shut down, detach
            # the image in Machine.boot(), then authenticate on the repaired disk.
            terminal.sendline('sudo -n poweroff')
            shutdown_deadline = time.monotonic() + 120
            while machine.process.poll() is None and time.monotonic() < shutdown_deadline:
                try:
                    terminal.read_nonblocking(65536, timeout=1)
                except pexpect.TIMEOUT:
                    continue
                except pexpect.EOF:
                    break
            machine.process.wait(timeout=120)
        finally:
            channel.close()
    machine.stop()
