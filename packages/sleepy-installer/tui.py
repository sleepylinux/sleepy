#!/usr/bin/env python3
"""Sleepy's terminal-only installation wizard; privilege lives in backend.py."""
import json
import locale
import os
from pathlib import Path
import subprocess
import sys
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from backend import encryption_passphrase_valid, hostname_valid, username_valid

OPTIONS = {
    'nvidia': 'NVIDIA (Turing/newer, open kernel driver)',
    'gaming': 'Steam / Proton and gaming tools',
    'development': 'Git, direnv and development tools',
    'flatpak': 'Flatpak GUI applications',
    'bluetooth': 'Bluetooth devices and settings',
}
BACKTITLE = 'S L E E P Y   /   a little space to make your own'
FOOTER = '↑↓ Move   ·   Space Select   ·   Tab Buttons   ·   Enter Continue'


def clean(value):
    """Do not let hardware strings or backend diagnostics control the terminal."""
    return ''.join(c for c in str(value) if c == '\n' or (c.isprintable() and c != '\x7f'))


def backend_command(operation):
    executable = os.environ.get('SLEEPY_BACKEND', 'sleepy-install-backend')
    return ['sudo', '-n', '--', executable, operation]


class Dialog:
    def __init__(self):
        self.env = dict(os.environ)
        self.env.setdefault('TERM', 'xterm')
        theme = Path(__file__).with_name('dialogrc')
        if theme.exists():
            self.env['DIALOGRC'] = str(theme)

    def command(self, title):
        return ['dialog', '--backtitle', BACKTITLE, '--title', f' {title} ',
                '--no-shadow', '--no-mouse', '--ok-label', 'Continue',
                '--cancel-label', 'Back', '--output-fd', '1']

    def ask(self, title, kind, text, *items, default=None):
        command = self.command(title)
        if default is not None and kind in ('menu', 'radiolist'):
            command += ['--default-item', default]
        if kind == 'checklist':
            command += ['--separate-output']
        is_list = kind in ('menu', 'radiolist', 'checklist')
        command += ['--' + kind, text, '22', '76']
        if is_list:
            stride = 2 if kind == 'menu' else 3
            command += [str(min(8, len(items) // stride))]
        command += list(items)
        result = subprocess.run(command, stdout=subprocess.PIPE, env=self.env, text=True)
        if result.returncode in (1, 255):
            return None
        if result.returncode != 0:
            raise RuntimeError('The terminal dialog could not open. Use an 80 × 24 terminal with TERM=xterm.')
        return result.stdout.rstrip('\n')

    def message(self, title, text):
        subprocess.run(self.command(title) + ['--msgbox', text, '22', '76'], env=self.env, check=True)


def list_disks():
    result = subprocess.run(backend_command('--list'), capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Cannot inspect disks. Check the installer service and sudo configuration.')
    return json.loads(result.stdout)


def disk_description(disk):
    gib = int(disk['size']) / (1024 ** 3)
    return f"{clean(disk['model'])}  ·  {gib:.1f} GiB  ·  serial {clean(disk.get('serial') or 'unavailable')}"


def clear_secrets(request, encryption_only=False):
    fields = ('encryption_passphrase', 'encryption_passphrase_confirm')
    if not encryption_only:
        fields += ('password', 'password_confirm')
    for field in fields:
        request.pop(field, None)


def install(dialog, request):
    """Send secrets through stdin only; display structured backend events."""
    process = None
    gauge = None
    message = 'Installation did not finish. Open Recovery for diagnostics.'
    completed = False
    try:
        process = subprocess.Popen(backend_command('--install'), stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        process.stdin.write(json.dumps(request, ensure_ascii=True) + '\n')
        process.stdin.close()
        clear_secrets(request)
        gauge = subprocess.Popen(dialog.command('Installing Sleepy') + [
            '--gauge', 'Preparing your new home…\n\nKeep the computer powered on.', '12', '76', '0'],
            stdin=subprocess.PIPE, env=dialog.env, text=True)
        for line in process.stdout:
            try:
                event = json.loads(line)
                progress = max(0, min(100, int(event.get('progress', 0))))
                message = clean(event.get('message', 'Working…'))
                completed = event.get('stage') == 'complete'
            except (ValueError, TypeError, AttributeError):
                continue
            if gauge.poll() is None:
                # dialog's gauge protocol uses XXX as a record delimiter.
                safe_message = '\n'.join(' ' + row for row in message.splitlines())
                try:
                    gauge.stdin.write(f'XXX\n{progress}\n{safe_message}\n\n Keep the computer powered on.\nXXX\n')
                    gauge.stdin.flush()
                except BrokenPipeError:
                    pass
        success = process.wait() == 0 and completed
    finally:
        clear_secrets(request)
        if gauge is not None:
            try:
                gauge.stdin.close()
            except BrokenPipeError:
                pass
            gauge.wait()
        if process is not None:
            if process.poll() is None:
                process.terminate()
                process.wait()
            process.stdout.close()
    if not success:
        dialog.message('Installation stopped', message + '\n\nThe disk may be partially installed. Erased data cannot be restored by this installer. Return to the menu for network settings or recovery, then retry.')
    return success


def input_step(dialog, title, prompt, default='', validator=None, secret=False, invalid_message='Please enter a valid value.'):
    while True:
        answer = dialog.ask(title, 'passwordbox' if secret else 'inputbox', prompt,
                            *([] if secret else [default]))
        if answer is None:
            return None
        if validator is None or validator(answer):
            return answer
        dialog.message('A small adjustment', invalid_message + '\n\n' + prompt)


def timezone_valid(value):
    try:
        ZoneInfo(value)
        return True
    except (ValueError, ZoneInfoNotFoundError):
        return False


def collect_request(dialog, disk):
    request = {'disk': disk['path'], 'identity': disk['identity']}
    steps = [
        ('username', '2 / 5   Your account', 'Username\n\nLowercase letters, numbers, hyphens and underscores; start with a letter.\nSystem account names and nixbld / systemd- prefixes are reserved.', 'sleepy',
         username_valid, False),
        ('password', '2 / 5   Your account', 'Choose your login password.\n\nAt least 8 characters. Your input stays hidden.\nThe installer uses the US keyboard for your password.', '', lambda v: len(v) >= 8, True),
        ('password_confirm', '2 / 5   Your account', 'Type your password again.\n\nYour input stays hidden.', '', lambda v: v == request.get('password'), True),
        ('hostname', '2 / 5   Your account', 'Computer name\n\nA short name for this machine on your network.', 'sleepy',
         hostname_valid, False),
    ]
    locale_choices = ['en_US.UTF-8', 'English (United States)', 'ru_RU.UTF-8', 'Русский',
                      'de_DE.UTF-8', 'Deutsch', 'cs_CZ.UTF-8', 'Čeština']
    keyboard_choices = ['us', 'English (US)', 'ru', 'US + Russian', 'de', 'US + German', 'cz', 'US + Czech']
    index = 0
    while index < 11:
        if index < len(steps):
            key, title, prompt, default, validator, secret = steps[index]
            answer = input_step(dialog, title, prompt, request.get(key, default), validator, secret)
        elif index in (4, 5):
            key, label, choices, default = (
                ('locale', 'Language', locale_choices, 'en_US.UTF-8') if index == 4 else
                ('keyboard', 'Installed desktop keyboard layout', keyboard_choices, 'us'))
            if key == 'keyboard':
                label += '\n\nDesktop: US stays available; Alt+Shift switches added layouts.\nRecovery consoles always use US, like this installer.'
            answer = dialog.ask('3 / 5   Make it feel familiar', 'menu', label + '\n\n' + FOOTER,
                                *choices, default=request.get(key, default))
        elif index == 6:
            key = 'timezone'
            answer = input_step(dialog, '3 / 5   Make it feel familiar',
                                'Timezone\n\nUse a timezone name, for example Europe/Prague or America/New_York.',
                                request.get(key, 'UTC'), timezone_valid)
        elif index == 7:
            key = 'options'
            current = request.get(key, {})
            items = [part for name, label in OPTIONS.items()
                     for part in (name, label, 'on' if current.get(name) else 'off')]
            answer = dialog.ask('4 / 5   Only what you need', 'checklist',
                                'A minimal Sleepy desktop is included. Everything below is optional.\n'
                                'NVIDIA and gaming require proprietary software licenses.\n\n' + FOOTER, *items)
            if answer is not None:
                selected = set(answer.splitlines())
                answer = {name: name in selected for name in OPTIONS}
        elif index == 8:
            key = 'encryption'
            answer = dialog.ask('4 / 5   Protect your files', 'menu',
                'Optional disk encryption\n\n'
                'Encryption protects your files when this computer is off.\n'
                'You must enter a separate disk passphrase at every boot.\n'
                'Startup and recovery always use the US keyboard.\n'
                'Keep this passphrase safe: Sleepy cannot recover a forgotten one.\n\n' + FOOTER,
                'off', 'No encryption — simplest startup',
                'on', 'Encrypt this disk — passphrase at every boot',
                default='on' if request.get('encryption', False) else 'off')
            if answer is not None:
                answer = answer == 'on'
                if not answer:
                    clear_secrets(request, encryption_only=True)
        else:
            key = 'encryption_passphrase' if index == 9 else 'encryption_passphrase_confirm'
            prompt = ('Choose your disk passphrase.\n\n'
                      '12–128 printable ASCII characters; spaces are allowed.\n'
                      'Use the US keyboard, also used to unlock the disk at startup.\n'
                      'Your input stays hidden.' if index == 9 else
                      'Type your disk passphrase again.\n\nYour input stays hidden. US keyboard.')
            validator = encryption_passphrase_valid if index == 9 else lambda value: value == request.get('encryption_passphrase')
            answer = input_step(dialog, '4 / 5   Protect your files', prompt,
                                validator=validator, secret=True,
                                invalid_message=('Use 12–128 printable ASCII characters (spaces allowed).' if index == 9 else
                                                 'The disk passphrases do not match.'))
        if answer is None:
            if index >= 8:
                clear_secrets(request, encryption_only=True)
            if index == 0:
                request.clear()
                return None
            index -= 1
            continue
        request[key] = answer
        index = 11 if key == 'encryption' and not answer else index + 1
    request.pop('encryption_passphrase_confirm', None)
    request.pop('password_confirm', None)
    return request


def wizard(dialog):
    while True:
        action = dialog.ask('Welcome home', 'menu',
            '       s l e e p y\n\nA quiet tiling desktop. A small beginning.\n\n'
            'Install on a whole disk with UEFI boot and Btrfs.\n'
            'Internet access is required to download the desktop.\n\n' + FOOTER,
            'install', 'Install Sleepy', 'network', 'Connect to Wi-Fi / configure network',
            'recovery', 'Recovery and diagnostics', 'exit', 'Leave installer')
        if action in (None, 'exit'):
            return
        if action == 'network':
            subprocess.run(['nmtui'], check=False)
            continue
        if action == 'recovery':
            from recovery_tui import wizard as recovery_wizard
            recovery_wizard(dialog)
            continue
        request = None
        try:
            disks = list_disks()
            eligible = {disk['path']: disk for disk in disks if disk['eligible']}
            if not eligible:
                details = '\n'.join(f"{clean(d['path'])}: {clean(d.get('reason', 'unavailable'))}" for d in disks)
                dialog.message('No available disk', 'No unused whole disk is available.\n\n' + details)
                continue
            choice = dialog.ask('1 / 5   A place for Sleepy', 'menu',
                'Choose the entire disk to erase.\nMounted or busy disks are excluded.\n\n' + FOOTER,
                *[part for path, disk in eligible.items() for part in (path, disk_description(disk))])
            if choice is None:
                continue
            disk = eligible[choice]
            request = collect_request(dialog, disk)
            if request is None:
                continue
            selected = ', '.join(key for key, enabled in request['options'].items() if enabled) or 'none'
            summary = (f"ERASE ALL DATA on {clean(choice)}\n{disk_description(disk)}\n\n"
                       f"Account: {request['username']} @ {request['hostname']}\n"
                       f"Region: {request['locale']} / {request['timezone']}\n"
                       + ("Keyboard: US\n" if request['keyboard'] == 'us' else
                          f"Keyboard: US + {request['keyboard']} (Alt+Shift)\n")
                       + f"Optional software: {selected}\n"
                       + ("Encryption: on — disk passphrase at every boot (US keyboard)\n\n" if request.get('encryption', False) else
                          "Encryption: off\n\n")
                       + 'All existing partitions and files on this disk will be destroyed.\n'
                       'There is no undo. Check the disk identity above.\n\n'
                       f'Type the full disk path {choice} to begin:')
            confirmation = input_step(dialog, '5 / 5   One last check', summary,
                                      validator=lambda v: v == choice, invalid_message='The disk path does not match. Nothing has been erased.')
            if confirmation is None:
                clear_secrets(request)
                continue
            request['confirm_erase'] = confirmation
            if not install(dialog, request):
                continue
            action = dialog.ask('Your new home is ready', 'menu',
                'Sleepy was installed successfully.\n\n'
                '1. Shut down this machine.\n2. Remove the installer image / USB.\n'
                '3. Boot the installed disk and sign in with your new password.',
                'shutdown', 'Shut down now', 'exit', 'Return to the installation terminal')
            if action == 'shutdown':
                subprocess.run(['sudo', '-n', '--', 'systemctl', 'poweroff'], check=True)
            return
        except (OSError, RuntimeError, ValueError, KeyError) as error:
            dialog.message('Something needs attention', clean(error))
        finally:
            if request is not None:
                clear_secrets(request)


def main():
    locale.setlocale(locale.LC_ALL, '')
    try:
        wizard(Dialog())
    except KeyboardInterrupt:
        print('\nSleepy installer closed. Run sleepy-install to return.', file=sys.stderr)
        return 130
    return 0


if __name__ == '__main__':
    sys.exit(main())
