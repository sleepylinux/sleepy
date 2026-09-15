#!/usr/bin/env python3
"""Guided boot-entry repair; privilege and installed-path handling stay in recovery.py."""
import json
import os
import subprocess
import signal
import sys

from tui import Dialog, clean, clear_secrets, disk_description, input_step, list_disks
from backend import encryption_passphrase_valid


def command(operation):
    return ['sudo', '-n', '--', os.environ.get('SLEEPY_RECOVERY_BACKEND', 'sleepy-recover-backend'), operation]


def stop_process(process):
    if process.poll() is not None: return
    try: os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError: pass
    try: process.wait(timeout=15)
    except subprocess.TimeoutExpired:
        try: os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError: pass
        process.wait(timeout=5)


def inspect(request):
    process = subprocess.Popen(command('--inspect'), stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL, text=True, start_new_session=True)
    try:
        output, _ = process.communicate(json.dumps(request), timeout=120)
    finally:
        stop_process(process)
    data = json.loads(output)
    if process.returncode:
        raise RuntimeError(data.get('message', 'Inspection failed; see /var/log/sleepy-installer.log'))
    return data


def restore(dialog, request):
    process = None
    gauge = None
    complete = False
    message = 'Repair did not finish; see /var/log/sleepy-installer.log.'
    try:
        process = subprocess.Popen(command('--restore'), stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, start_new_session=True)
        process.stdin.write(json.dumps(request)); process.stdin.close()
        clear_secrets(request)
        gauge = subprocess.Popen(dialog.command('Restoring boot entries') + ['--gauge', 'Preparing boot repair… Keep the computer powered on.', '12', '76', '0'], stdin=subprocess.PIPE, text=True, env=dialog.env)
        for line in process.stdout:
            event = json.loads(line)
            message = clean(event.get('message', 'Working…'))
            complete = event.get('stage') == 'complete'
            if gauge.poll() is None:
                text = '\n'.join(' ' + row for row in message.splitlines())
                try:
                    gauge.stdin.write(f"XXX\n{max(0, min(100, int(event.get('progress', 0))))}\n{text}\n Keep the computer powered on.\nXXX\n")
                    gauge.stdin.flush()
                except BrokenPipeError: pass
        succeeded = process.wait() == 0 and complete
    finally:
        clear_secrets(request)
        if process is not None:
            stop_process(process)
            process.stdout.close()
        if gauge is not None:
            try: gauge.stdin.close()
            except BrokenPipeError: pass
            gauge.wait()
    dialog.message('Boot repair complete' if succeeded else 'Boot repair stopped', message)
    return succeeded


def wizard(dialog):
    while True:
        request = None
        try:
            disks = [disk for disk in list_disks() if disk['eligible']]
            items = [value for disk in disks for value in (disk['path'], disk_description(disk))]
            selected = dialog.ask('Recover Sleepy boot', 'menu',
                'Inspect an installed Sleepy disk without changing it.\n'
                'Supports Sleepy GPT / EFI / Btrfs installations, including LUKS2.\n'
                'Encrypted disks require their disk passphrase (US keyboard).',
                *items, 'back', 'Return to the installer', default=disks[0]['path'] if disks else 'back')
            if selected in (None, 'back'): return
            disk = next(disk for disk in disks if disk['path'] == selected)
            request = dict(disk=disk['path'], identity=disk['identity'])
            metadata = inspect(request)
            if metadata.get('encrypted') is True and metadata.get('locked') is True:
                passphrase = input_step(dialog, 'Unlock for boot recovery',
                    'Enter the disk passphrase, not your login password.\n\n'
                    'Use the US keyboard. Your input stays hidden.\n'
                    'Inspection reads the installed system without changing it.\n'
                    'Back returns without starting a repair.',
                    validator=encryption_passphrase_valid, secret=True,
                    invalid_message='Use 12–128 printable ASCII characters (spaces allowed).')
                if passphrase is None: continue
                request['encryption_passphrase'] = passphrase
                del passphrase
                metadata = inspect(request)
            retained = metadata['generations']
            generations = ', '.join(str(item['generation']) for item in retained[-12:])
            if len(retained) > 12: generations = '… ' + generations
            generations += f' ({len(retained)} total)'
            choice = dialog.ask('Installed Sleepy', 'menu',
                f"{clean(disk['path'])}\n{disk_description(disk)}\n\n"
                f"Current generation: {metadata['current']}\nRetained generations: {generations}\n\n"
                'Restore boot entries for this installation. The system profile\n'
                'and personal files are not rolled back. No packages are downloaded.',
                'restore', 'Restore boot entries', 'back', 'Back without changes', default='back')
            if choice != 'restore': continue
            confirm = dialog.ask('Confirm boot repair', 'inputbox',
                f"Selected disk: {clean(disk['path'])}\n{disk_description(disk)}\n\n"
                'This runs repair code from the installed OS as root.\n'
                'Continue only if you trust this installed system.\n'
                'It writes boot files and may update firmware boot entries.\n'
                'It does not recover erased data or reset your password.\n\n'
                f"Type {clean(disk['path'])} to confirm:", '')
            if confirm is None: continue
            if confirm != disk['path']:
                dialog.message('Confirmation did not match', 'No repair was started. Inspect the disk and try again.'); continue
            request.update(installation=metadata['installation'], confirm_restore=confirm)
            if restore(dialog, request): return
        except (OSError, ValueError, KeyError, StopIteration, RuntimeError, subprocess.TimeoutExpired) as error:
            dialog.message('Recovery needs attention', clean(error))
        finally:
            if request is not None:
                clear_secrets(request)


def main():
    try: wizard(Dialog())
    except KeyboardInterrupt: return 130
    return 0


if __name__ == '__main__': sys.exit(main())
