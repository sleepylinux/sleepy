#!/usr/bin/env python3
"""Boot a real installer ISO, drive its TUI, then boot/authenticate the installed disk.

Requires qemu-system-x86_64, qemu-img, OVMF, pexpect, Pillow, and tesseract.
Only disks created in a NEW output directory are used. Never attach a host disk.
This is an integration runner, not a replacement for a successful VM result.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import secrets
import shlex
import re
import shutil
import socket
import subprocess
import sys
import time
import threading

import pexpect.fdpexpect
from PIL import Image


class QMP:
    def __init__(self, path):
        self.socket = socket.socket(socket.AF_UNIX)
        deadline = time.monotonic() + 30
        while True:
            try:
                self.socket.connect(str(path)); break
            except (FileNotFoundError, ConnectionRefusedError):
                if time.monotonic() > deadline: raise
                time.sleep(.2)
        self.stream = self.socket.makefile('rwb', buffering=0)
        self.stream.readline()
        self.call('qmp_capabilities')

    def call(self, command, **arguments):
        self.stream.write((json.dumps({'execute': command, 'arguments': arguments}) + '\n').encode())
        while True:
            reply = json.loads(self.stream.readline())
            if 'error' in reply: raise RuntimeError(f'QMP {command}: {reply["error"]}')
            if 'return' in reply: return reply['return']

    def keys(self, *keys):
        self.call('send-key', keys=[{'type': 'qcode', 'data': key} for key in keys], **{'hold-time': 60})
        time.sleep(.09)

    def text(self, value):
        punctuation = {' ': 'spc', '-': 'minus', '=': 'equal', '[': 'bracket_left', ']': 'bracket_right',
                       ';': 'semicolon', "'": 'apostrophe', ',': 'comma', '.': 'dot', '/': 'slash',
                       '\\': 'backslash', '`': 'grave_accent', '\n': 'ret'}
        shifted = {'!': '1', '@': '2', '#': '3', '$': '4', '%': '5', '^': '6', '&': '7', '*': '8',
                   '(': '9', ')': '0', '_': 'minus', '+': 'equal', '{': 'bracket_left', '}': 'bracket_right',
                   ':': 'semicolon', '"': 'apostrophe', '<': 'comma', '>': 'dot', '?': 'slash',
                   '|': 'backslash', '~': 'grave_accent'}
        for char in value:
            if char.isascii() and char.isalnum():
                self.keys(*(['shift', char.lower()] if char.isupper() else [char]))
            elif char in shifted: self.keys('shift', shifted[char])
            elif char in punctuation: self.keys(punctuation[char])
            else: raise ValueError('Unsupported test keyboard character')

    def screenshot(self, path):
        ppm = path.with_suffix('.ppm')
        self.call('screendump', filename=str(ppm))
        with Image.open(ppm) as frame: frame.save(path)
        ppm.unlink()
        return subprocess.run(['tesseract', str(path), 'stdout'], capture_output=True, text=True, check=True).stdout

    def close(self):
        self.stream.close(); self.socket.close()


class Machine:
    def __init__(self, output, firmware, memory, acceleration):
        self.output, self.firmware, self.memory, self.acceleration = output, firmware, memory, acceleration
        self.process = None

    def boot(self, phase, iso=None):
        for name in ['qmp.sock', 'serial.sock', 'report.sock']:
            (self.output / name).unlink(missing_ok=True)
        self.log = (self.output / f'{phase}-qemu.log').open('w')
        command = ['qemu-system-x86_64', '-machine', f'q35,accel={self.acceleration}', '-m', str(self.memory),
                   '-smp', '4', '-cpu', 'host' if self.acceleration == 'kvm' else 'max',
                   '-drive', f'if=pflash,format=raw,readonly=on,file={self.firmware}',
                   '-drive', f'if=pflash,format=raw,file={self.output / "OVMF_VARS.fd"}',
                   '-drive', f'if=virtio,format=qcow2,file={self.output / "installed.qcow2"}',
                   '-device', 'virtio-vga', '-display', 'none',
                   '-device', 'virtio-net-pci,id=nic0,netdev=net0', '-netdev', 'user,id=net0',
                   '-qmp', f'unix:{self.output / "qmp.sock"},server=on,wait=off',
                   '-serial', f'unix:{self.output / "serial.sock"},server=on,wait=off',
                   '-device', 'virtio-serial-pci',
                   '-chardev', f'socket,id=report,path={self.output / "report.sock"},server=on,wait=off',
                   '-device', 'virtserialport,chardev=report,name=org.sleepy.test']
        if iso: command += ['-cdrom', str(iso), '-boot', 'order=d']
        else: command += ['-boot', 'order=c']
        self.process = subprocess.Popen(command, stdout=self.log, stderr=subprocess.STDOUT)
        self.qmp = QMP(self.output / 'qmp.sock')
        return self

    def stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                try: self.qmp.call('quit')
                except (OSError, ValueError): self.process.terminate()
            self.process.wait(timeout=20)
            self.qmp.close(); self.log.close(); self.process = None

    def screen(self, name):
        return self.qmp.screenshot(self.output / (name + '.png'))

    def wait_screen(self, fragment, name, timeout=180):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = self.screen(name)
            if fragment.lower() in text.lower(): return text
            if self.process.poll() is not None: raise RuntimeError('VM stopped unexpectedly')
            time.sleep(3)
        raise RuntimeError(f'Screen did not show {fragment!r}; inspect {name}.png')


def install(machine, password, timeout, cache_url=None, cache_public_key=None):
    # tty1 is the visible, automatically launched production TUI. Serial carries
    # boot diagnostics only: no parallel hidden installer or injected request.
    channel = socket.socket(socket.AF_UNIX)
    channel.connect(str(machine.output / 'serial.sock'))
    if cache_url:
        # Public transport hints only, supplied through the normal installer shell.
        # Signature verification stays enabled; the private signing key never enters VM.
        terminal = pexpect.fdpexpect.fdspawn(channel, encoding='utf-8', codec_errors='replace', timeout=300)
        with (machine.output / 'cache-transport.log').open('w') as cache_log:
            terminal.logfile_read = cache_log
            terminal.expect(r'\$ |# ')
            settings = ['extra-substituters = ' + cache_url,
                        'extra-trusted-public-keys = ' + cache_public_key,
                        'require-sigs = true']
            script = ('set -eu; cp /etc/nix/nix.conf /run/sleepy-cache-nix.conf; '
                      + 'printf \'%s\\n\' ' + ' '.join(shlex.quote(v) for v in [''] + settings)
                      + ' >> /run/sleepy-cache-nix.conf; rm /etc/nix/nix.conf; '
                      + 'cp /run/sleepy-cache-nix.conf /etc/nix/nix.conf; '
                      + 'systemctl restart nix-daemon; printf \'SLEEPY_CACHE_%s\\n\' READY')
            terminal.sendline('sudo -n sh -c ' + shlex.quote(script))
            terminal.expect('SLEEPY_CACHE_READY')
            terminal.logfile_read = None
    def record_serial():
        with (machine.output / 'installer-serial.log').open('wb') as log:
            try:
                while True:
                    chunk = channel.recv(4096)
                    if not chunk: break
                    log.write(chunk); log.flush()
            except OSError:
                pass
    recorder = threading.Thread(target=record_serial, daemon=True)
    recorder.start()
    try:
        machine.wait_screen('Welcome home', 'installer-welcome', timeout=300)
        machine.qmp.keys('ret')
        for prompt, screenshot, value in [
            ('A place for Sleepy', 'installer-disk', ''),
            ('Username', 'installer-user', ''),
            ('Choose your login password', 'installer-password', password),
            ('Type your password again', 'installer-password-confirm', password),
            ('Computer name', 'installer-hostname', ''),
            ('Language', 'installer-locale', ''),
            ('Installed keyboard layout', 'installer-keyboard', ''),
            ('Timezone', 'installer-timezone', ''),
            ('Only what you need', 'installer-options', ''),
        ]:
            machine.wait_screen(prompt, screenshot)
            machine.qmp.text(value + '\n')
        machine.wait_screen('One last check', 'installer-confirmation')
        machine.qmp.text('/dev/vda\n')
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = machine.screen('installer-progress')
            if 'Your new home is ready'.lower() in text.lower(): break
            if 'Installation stopped'.lower() in text.lower():
                machine.screen('installer-failed')
                raise RuntimeError('Real installer failed; inspect VM diagnostics')
            if machine.process.poll() is not None: raise RuntimeError('Installer VM exited before completion')
            time.sleep(10)
        else:
            raise RuntimeError('Real installer timed out; inspect installer-progress.png')
        machine.screen('installer-complete')
        machine.qmp.keys('ret')
        machine.process.wait(timeout=120)
    except Exception:
        # The separate serial login stays available for root-only diagnostics.
        try:
            channel.sendall(b'\nsudo tail -n 120 /var/log/sleepy-installer.log; lsblk -f\n')
            time.sleep(5)
        except OSError:
            pass
        raise
    finally:
        channel.close()
        recorder.join(timeout=2)


def guest_report(machine, password, stage, after_reboot=False):
    """Authenticate on a real VT, then explicitly sudo a fixed read-only audit."""
    machine.qmp.keys('ctrl', 'alt', 'f2')
    machine.wait_screen('login:', f'{stage}-console')
    machine.qmp.text('sleepy\n')
    machine.wait_screen('Password:', f'{stage}-password-prompt')
    machine.qmp.text(password + '\n')
    machine.wait_screen('sleepy@', f'{stage}-authenticated')
    channel = socket.socket(socket.AF_UNIX)
    channel.settimeout(120)
    channel.connect(str(machine.output / 'report.sock'))
    script = r'''#!/usr/bin/env bash
set -eu
exec > /dev/virtio-ports/org.sleepy.test 2>&1
trap 'printf "SLEEPY_REPORT_FAILED line=%s\n" "$LINENO"' ERR
printf 'SLEEPY_REPORT_START\n'
uid=$(cat /tmp/sleepy-alpha-uid)
test "$uid" -ge 1000
printf 'REAL_USER_LOGIN_OK\n'
test -d /sys/firmware/efi
findmnt -no SOURCE,FSTYPE /
findmnt -no SOURCE,FSTYPE /boot
test "$(findmnt -no FSTYPE /)" = btrfs
test -f /etc/nixos/flake.nix
! findmnt -rn -t iso9660 | grep .
printf 'INSTALLED_DISK_BOOT_OK\n'
systemctl is-active greetd
usystem() { runuser -u sleepy -- env XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus systemctl --user "$@"; }
for unit in graphical-session.target wayland-wm@hyprland.desktop.service sleepy-session.service sleepy-shell.service; do usystem is-active "$unit"; done
test -S /run/user/$uid/sleepy/desktop.sock
test "$(stat -c %a /run/user/$uid/sleepy/desktop.sock)" = 600
printf 'DESKTOP_UNITS_AND_SOCKET_OK\n'
for unit in sleepy-shell.service sleepy-session.service; do
  old=$(usystem show "$unit" -P MainPID)
  test "$old" -gt 1
  usystem kill --kill-whom=main --signal=KILL "$unit"
  changed=false
  for attempt in $(seq 1 40); do
    sleep 1
    new=$(usystem show "$unit" -P MainPID)
    if test "$new" -gt 1 && test "$new" != "$old" && usystem is-active --quiet "$unit"; then changed=true; break; fi
  done
  test "$changed" = true
  printf 'CRASH_RECOVERY_OK %s\n' "$unit"
done
test -S /run/user/$uid/sleepy/desktop.sock
usystem is-active sleepy-shell.service
''' + (r'''
test "$(cat /home/sleepy/.config/sleepy/alpha-persistence)" = sleepy-alpha-state
printf 'PERSISTENCE_AFTER_REBOOT_OK\n'
''' if after_reboot else r'''
runuser -u sleepy -- mkdir -p /home/sleepy/.config/sleepy
runuser -u sleepy -- sh -c 'printf sleepy-alpha-state > /home/sleepy/.config/sleepy/alpha-persistence'
sync
printf 'PERSISTENCE_MARKER_WRITTEN\n'
''') + r'''
printf 'SLEEPY_REPORT_COMPLETE\n'
'''
    # Transfer the fixed audit only AFTER normal password authentication and sudo.
    # The device is test hardware, not an installed service or authentication bypass.
    command = ("id -u > /tmp/sleepy-alpha-uid; sudo bash -c 'head -c " + str(len(script.encode())) +
               " /dev/virtio-ports/org.sleepy.test > /tmp/sleepy-alpha-check; bash /tmp/sleepy-alpha-check'\n")
    machine.qmp.text(command)
    machine.wait_screen('password for sleepy', f'{stage}-sudo-prompt')
    machine.qmp.text(password + '\n')
    channel.sendall(script.encode())
    report = b''
    deadline = time.monotonic() + 120
    try:
        while b'SLEEPY_REPORT_COMPLETE' not in report and b'SLEEPY_REPORT_FAILED' not in report:
            if time.monotonic() > deadline: raise RuntimeError('Guest audit did not complete')
            chunk = channel.recv(65536)
            if not chunk: break
            report += chunk
            if len(report) > 1024 * 1024: raise RuntimeError('Guest audit exceeded 1 MiB output bound')
    finally:
        channel.close()
        (machine.output / f'{stage}-guest-report.txt').write_bytes(report)
    if b'SLEEPY_REPORT_COMPLETE' not in report:
        raise RuntimeError(f'Installed guest audit failed; inspect {stage}-guest-report.txt')
    machine.qmp.text('exit\n')
    machine.qmp.keys('ctrl', 'alt', 'f1')
    return report.decode(errors='replace')


def login_desktop(machine, password, name):
    machine.wait_screen('Sleepy', f'{name}-greeter', timeout=300)
    machine.qmp.keys('ret')
    machine.wait_screen('Password', f'{name}-greeter-password')
    machine.qmp.text(password + '\n')
    time.sleep(20)
    machine.screen(f'{name}-desktop')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iso', required=True, type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--firmware', type=Path, default=Path('/usr/share/edk2/x64/OVMF_CODE.4m.fd'))
    parser.add_argument('--vars', type=Path, default=Path('/usr/share/edk2/x64/OVMF_VARS.4m.fd'))
    parser.add_argument('--memory', type=int, default=8192)
    parser.add_argument('--install-timeout', type=int, default=10800)
    parser.add_argument('--cache-url', help='Optional signed binary cache reachable inside VM (e.g. http://10.0.2.2:8080)')
    parser.add_argument('--cache-public-key', help='Public signing key for the optional cache; private key must stay on host')
    args = parser.parse_args()
    output, iso = args.output.resolve(), args.iso.resolve()
    if bool(args.cache_url) != bool(args.cache_public_key): parser.error('--cache-url and --cache-public-key must be supplied together')
    if args.cache_url and not re.fullmatch(r'https?://[A-Za-z0-9.:/_-]+', args.cache_url): parser.error('Invalid cache URL')
    if args.cache_public_key and not re.fullmatch(r'[A-Za-z0-9._-]+:[A-Za-z0-9+/]+=*', args.cache_public_key): parser.error('Invalid public signing key')
    if not iso.is_file(): parser.error('ISO does not exist')
    if output.exists(): parser.error('Output directory must not already exist; existing disks are never reused')
    for tool in ['qemu-system-x86_64', 'qemu-img', 'tesseract']:
        if shutil.which(tool) is None: parser.error(f'Missing tool: {tool}')
    if not args.firmware.is_file() or not args.vars.is_file(): parser.error('OVMF firmware missing')
    output.mkdir(parents=True, mode=0o700)
    os.chmod(output, 0o700)
    subprocess.run(['qemu-img', 'create', '-f', 'qcow2', str(output / 'installed.qcow2'), '40G'], check=True)
    shutil.copyfile(args.vars, output / 'OVMF_VARS.fd')
    password = secrets.token_hex(12)
    # Recovery credential stays local/private; never embed it in logs or command argv.
    fd = os.open(output / 'test-credential', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w') as secret_file: secret_file.write(password + '\n')
    acceleration = 'kvm' if os.access('/dev/kvm', os.R_OK | os.W_OK) else 'tcg'
    result = {'status': 'running', 'iso': str(iso), 'iso_sha256': hashlib.file_digest(iso.open('rb'), 'sha256').hexdigest(),
              'acceleration': acceleration, 'cache_transport': args.cache_url, 'cache_public_key': args.cache_public_key, 'completed': [], 'source_revision': subprocess.run(
                  ['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip()}
    machine = Machine(output, args.firmware.resolve(), args.memory, acceleration)
    try:
        print('Booting installer and driving the visible tty1 TUI.', flush=True)
        machine.boot('installer', iso)
        install(machine, password, args.install_timeout, args.cache_url, args.cache_public_key)
        result['completed'].append('tui-install-and-shutdown')
        machine.stop()
        print('Booting installed disk without installer media.', flush=True)
        machine.boot('installed')
        login_desktop(machine, password, 'installed')
        guest_report(machine, password, 'installed')
        result['completed'] += ['installed-disk-boot', 'real-password-login', 'desktop-units-and-socket',
                                'shell-SIGKILL-recovery', 'session-daemon-SIGKILL-recovery']
        # An ACPI shutdown exercises normal system cleanup before the next boot.
        machine.qmp.call('system_powerdown')
        machine.process.wait(timeout=120)
        machine.stop()
        machine.boot('offline-reboot')
        machine.qmp.call('set_link', name='nic0', up=False)
        login_desktop(machine, password, 'offline-reboot')
        guest_report(machine, password, 'offline-reboot', after_reboot=True)
        result['completed'] += ['offline-disk-reboot', 'offline-password-login', 'user-state-persistence']
        result['status'] = 'passed'
    except Exception as error:
        result['status'] = 'failed'
        result['error'] = str(error)
        if machine.process is not None and machine.process.poll() is None:
            try: machine.screen('failure')
            except Exception: pass
        print(f'VM check failed: {error}', file=sys.stderr)
    finally:
        machine.stop()
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Result and evidence: {output}', flush=True)
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
