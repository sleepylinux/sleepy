#!/usr/bin/env python3
"""Boot a real installer ISO, drive its TUI, then boot/authenticate the installed disk.

Requires qemu-system-x86_64, qemu-img, OVMF, pexpect, Pillow, and tesseract.
Only disks created in a NEW output directory are used. Never attach a host disk.
This is an integration runner, not a replacement for a successful VM result.
"""
import argparse
import boot_recovery
import base64
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
import tempfile

import pexpect.fdpexpect
from PIL import Image, ImageOps


def ocr_image(path):
    original = subprocess.run(['tesseract', str(path), 'stdout'], capture_output=True, text=True, check=True).stdout
    # VGA console glyphs are tiny. Analyze a temporary 3x Lanczos,
    # high-contrast copy calibrated against actual VGA console captures while preserving the original evidence screenshot.
    with Image.open(path) as frame, tempfile.TemporaryDirectory(prefix='sleepy-ocr-') as directory:
        enhanced = ImageOps.autocontrast(ImageOps.invert(frame.convert('L')))
        enhanced = enhanced.resize((frame.width * 3, frame.height * 3), Image.Resampling.LANCZOS)
        target = Path(directory) / 'analysis.png'
        enhanced.save(target)
        enlarged = '\n'.join(subprocess.run(['tesseract', str(target), 'stdout', '--psm', str(psm)],
                                  capture_output=True, text=True, check=True).stdout for psm in (6, 11))
    text = original + '\n' + enlarged
    if 'your desktop is ready to explore' in ' '.join(text.lower().split()):
        # Older alpha welcome dialogs used blue text on gray; preserve exact
        # title recognition in recovery runs without weakening string matching.
        with Image.open(path) as frame, tempfile.TemporaryDirectory(prefix='sleepy-welcome-ocr-') as directory:
            frame = frame.convert('RGB')
            mask = Image.new('L', frame.size)
            mask.putdata([0 if b - r > 25 and b - g > 10 else 255
                          for r, g, b in getattr(frame, 'get_flattened_data', frame.getdata)()])
            target = Path(directory) / 'title.png'
            mask.resize((frame.width * 3, frame.height * 3)).save(target)
            text += '\n' + subprocess.run(['tesseract', str(target), 'stdout', '--psm', '11'],
                                           capture_output=True, text=True, check=True).stdout
    return text


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
        text = ocr_image(path)
        path.with_suffix('.ocr.txt').write_text(text)
        return text

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
                   '-drive', f'if=none,id=installed-disk,format=qcow2,file={self.output / "installed.qcow2"}',
                   '-device', f'virtio-blk-pci,drive=installed-disk,bootindex={2 if iso else 1}',
                   '-device', 'virtio-vga', '-display', 'none',
                   '-device', 'virtio-net-pci,id=nic0,netdev=net0', '-netdev', 'user,id=net0',
                   '-qmp', f'unix:{self.output / "qmp.sock"},server=on,wait=off',
                   '-serial', f'unix:{self.output / "serial.sock"},server=on,wait=off',
                   '-device', 'virtio-serial-pci',
                   '-chardev', f'socket,id=report,path={self.output / "report.sock"},server=on,wait=off',
                   '-device', 'virtserialport,chardev=report,name=org.sleepy.test']
        if getattr(self, 'daily_usability', False):
            command += ['-audiodev', 'none,id=audio0', '-device', 'intel-hda',
                        '-device', 'hda-duplex,audiodev=audio0', '-device', 'qemu-xhci',
                        '-device', 'usb-tablet']
        # Explicit firmware device order also applies when OVMF retains an
        # installed-disk BootOrder. Do not mix bootindex with legacy -boot order.
        if iso:
            command += ['-drive', f'if=none,id=installer-media,format=raw,media=cdrom,readonly=on,file={iso}',
                        '-device', 'ide-cd,drive=installer-media,bus=ide.0,bootindex=1']
        offline_start = getattr(self, 'flatpak_recovery', False) and phase == 'installed'
        if offline_start: command += ['-S']
        self.process = subprocess.Popen(command, stdout=self.log, stderr=subprocess.STDOUT)
        self.qmp = QMP(self.output / 'qmp.sock')
        if offline_start:
            self.qmp.call('set_link', name='nic0', up=False)
            self.qmp.call('cont')
        return self

    def stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                try: self.qmp.call('quit')
                except (OSError, ValueError, RuntimeError): self.process.terminate()
            self.process.wait(timeout=20)
            self.qmp.close(); self.log.close(); self.process = None

    def screen(self, name):
        return self.qmp.screenshot(self.output / (name + '.png'))

    def wait_screen(self, fragment, name, timeout=180):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            text = self.screen(name)
            fragments = [fragment] if isinstance(fragment, str) else fragment
            normalized = ' '.join(text.lower().split())
            if all(' '.join(part.lower().split()) in normalized for part in fragments): return text
            if self.process.poll() is not None: raise RuntimeError('VM stopped unexpectedly')
            time.sleep(3)
        raise RuntimeError(f'Screen did not show {fragment!r}; inspect {name}.png')


SHELL_PROMPT = r'[$#](?:\x1b\[[0-9;]*m)* '


def serial_line(terminal, command, marker=None, timeout=300):
    terminal.sendline(command)
    if marker is not None:
        terminal.expect(marker, timeout=timeout)
    # sudo/login restore terminal modes on exit. Wait until bash owns the TTY
    # again; sending after a progress marker alone can be lost by TCSAFLUSH.
    terminal.expect(SHELL_PROMPT, timeout=timeout)


def safety_checks(machine, terminal, interrupt_install=False):
    script = r'''import fcntl, json, os, secrets, shutil, signal, subprocess, sys
backend = shutil.which("sleepy-install-backend")
disks = json.loads(subprocess.check_output([backend, "--list"], text=True))
disk = next(d for d in disks if d["path"] == "/dev/vda")
assert disk["eligible"], disk["reason"]
assert not any(d["eligible"] for d in disks if d["path"] == "/dev/sr0")
def no_partitions():
    value = json.loads(subprocess.check_output(["lsblk", "--json", "/dev/vda"], text=True))
    assert not value["blockdevices"][0].get("children"), "Disposable disk was modified"
no_partitions()
mode = sys.argv[1]
data = dict(disk="/dev/vda", identity=disk["identity"], confirm_erase="/dev/vda", username="sleepy", password=secrets.token_hex(16), hostname="sleepy", locale="en_US.UTF-8", keyboard="us", timezone="UTC", options={})
if mode == "invalid":
    data.update(disk="/dev/sr0", confirm_erase="/dev/sr0", identity="0"*64)
if mode == "interrupt":
    subprocess.run(["nm-online", "-q", "--timeout=30"], check=True)
    process = subprocess.Popen([backend, "--install"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    process.stdin.write(json.dumps(data)); process.stdin.close(); data.clear()
    interrupted = False
    try:
        for line in process.stdout:
            event = json.loads(line)
            if event["stage"] == "configure":
                os.kill(process.pid, signal.SIGTERM)
                interrupted = True
                break
        assert interrupted, "Installation failed before mounted-filesystem interruption point"
        assert process.wait(timeout=40) != 0, "Interrupted backend unexpectedly succeeded"
    finally:
        if process.poll() is None:
            process.terminate(); process.wait(timeout=40)
    value = json.loads(subprocess.check_output(["lsblk", "--json", "--output", "PATH,MOUNTPOINTS", "/dev/vda"], text=True))
    def unmounted(node):
        assert not any(node.get("mountpoints") or []), "Interrupted installation left mounted target"
        for child in node.get("children", []): unmounted(child)
    unmounted(value["blockdevices"][0])
    with open("/run/sleepy-installer.lock", "r+") as lock: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
else:
    result = subprocess.run([backend, "--install"], input=json.dumps(data), capture_output=True, text=True, timeout=180)
    data.clear()
    assert result.returncode != 0, "Unsafe request unexpectedly succeeded"
    event = json.loads(result.stdout.splitlines()[-1])
    assert event["stage"] == "error", event
    assert ("identity changed" if mode == "invalid" else "Connect the network") in event["message"], event
    no_partitions()
print("SLEEPY_SAFETY_" + mode.upper() + "_OK", flush=True)
'''
    encoded = base64.b64encode(script.encode()).decode()
    # Discover the interpreter already bundled in the immutable package wrapper.
    setup = ("sleepy_python=$(grep -oE '/nix/store/[a-z0-9]+-python3-[^/]+/bin/python3' "
             '\"$(readlink -f \"$(command -v sleepy-install-backend)\")\" | head -n1); : > /tmp/sleepy-safety.b64')
    serial_line(terminal, setup)
    # Stay well below the canonical terminal's input-line bound.
    for offset in range(0, len(encoded), 512):
        serial_line(terminal, 'printf %s ' + shlex.quote(encoded[offset:offset + 512]) + ' >> /tmp/sleepy-safety.b64')
    serial_line(terminal, 'base64 -d /tmp/sleepy-safety.b64 > /tmp/sleepy-safety.py')
    serial_line(terminal, 'sudo -n "$sleepy_python" /tmp/sleepy-safety.py invalid', 'SLEEPY_SAFETY_INVALID_OK', timeout=240)
    machine.safety_completed = ['invalid-target-rejected-without-disk-writes']
    machine.qmp.call('set_link', name='nic0', up=False)
    try:
        serial_line(terminal, 'sudo -n "$sleepy_python" /tmp/sleepy-safety.py offline', 'SLEEPY_SAFETY_OFFLINE_OK', timeout=240)
        machine.safety_completed.append('offline-install-rejected-without-disk-writes')
    except Exception:
        # Do not restore connectivity while an unexpected backend may still run.
        # main() stops the disposable VM on this failure.
        raise
    else:
        machine.qmp.call('set_link', name='nic0', up=True)
    if interrupt_install:
        serial_line(terminal, 'sudo -n "$sleepy_python" /tmp/sleepy-safety.py interrupt', 'SLEEPY_SAFETY_INTERRUPT_OK', timeout=300)
        machine.safety_completed.append('real-install-SIGTERM-cleanup-and-lock-release')



def install(machine, password, timeout, cache_url=None, cache_public_key=None, interrupt_install=False, keyboard="us"):
    # tty1 is the visible, automatically launched production TUI. Serial carries
    # boot diagnostics only: no parallel hidden installer or injected request.
    channel = socket.socket(socket.AF_UNIX)
    channel.connect(str(machine.output / 'serial.sock'))
    terminal = pexpect.fdpexpect.fdspawn(channel, encoding='utf-8', codec_errors='replace', timeout=300)
    boot_log = (machine.output / 'installer-serial-bootstrap.log').open('w')
    terminal.logfile_read = boot_log
    terminal.expect(SHELL_PROMPT)
    if cache_url:
        # Public transport hints only, supplied through the normal installer shell.
        # Signature verification stays enabled; the private signing key never enters VM.
        with (machine.output / 'cache-transport.log').open('w') as cache_log:
            terminal.logfile_read = cache_log
            settings = ['extra-substituters = ' + cache_url,
                        'extra-trusted-public-keys = ' + cache_public_key,
                        'require-sigs = true']
            script = ('set -eu; cp /etc/nix/nix.conf /run/sleepy-cache-nix.conf; '
                      + 'printf \'%s\\n\' ' + ' '.join(shlex.quote(v) for v in [''] + settings)
                      + ' >> /run/sleepy-cache-nix.conf; rm /etc/nix/nix.conf; '
                      + 'cp /run/sleepy-cache-nix.conf /etc/nix/nix.conf; '
                      + 'systemctl restart nix-daemon; printf \'SLEEPY_CACHE_%s\\n\' READY')
            serial_line(terminal, 'sudo -n sh -c ' + shlex.quote(script), 'SLEEPY_CACHE_READY')
            terminal.logfile_read = None
    with (machine.output / 'installer-safety.log').open('w') as safety_log:
        terminal.logfile_read = safety_log
        safety_checks(machine, terminal, interrupt_install)
        terminal.logfile_read = None
    boot_log.close()
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
            (('Choose your login', 'Your input stays hidden'), 'installer-password', password),
            (('Type your', 'again', 'Your input stays hidden'), 'installer-password-confirm', password),
            ('Computer name', 'installer-hostname', ''),
            ('Language', 'installer-locale', ''),
            ('Installed desktop keyboard layout', 'installer-keyboard', ''),
            ('Timezone', 'installer-timezone', ''),
            ('Only what you need', 'installer-options', ''),
        ]:
            machine.wait_screen(prompt, screenshot)
            if screenshot == 'installer-keyboard':
                for _ in range(('us', 'ru', 'de', 'cz').index(keyboard)):
                    machine.qmp.keys('down')
                machine.screen('installer-keyboard-selected')
            if screenshot == 'installer-options' and getattr(machine, 'flatpak_recovery', False):
                for _ in range(3): machine.qmp.keys('down')
                machine.qmp.keys('spc')
                machine.screen('installer-flatpak-selected')
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


def update_fixture(phase):
    user_environment = r'''
development_user() { runuser -u sleepy -- env HOME=/home/sleepy XDG_CONFIG_HOME=/home/sleepy/.config PATH=/etc/profiles/per-user/sleepy/bin:/home/sleepy/.nix-profile/bin:/run/current-system/sw/bin "$@"; }
'''
    if phase == 'seed':
        return user_environment + r'''
state=/var/lib/sleepy-alpha
development_user sh -c 'cd "$HOME"; ! command -v direnv'
printf 'DEVELOPMENT_ABSENT_IN_BASE_GENERATION_OK\n'
install -d -m 0700 "$state"
config=/etc/nixos/configuration.nix
head -n 1 "$config" | grep -Fx '{ ... }: {'
test ! -e /etc/nixos/alpha-update.nix
cp -p "$config" "$state/configuration.before"
cleanup_update() { cp -p "$state/configuration.before" "$config"; rm -f /etc/nixos/alpha-update.nix; }
trap cleanup_update EXIT
readlink -f /run/current-system > "$state/generation1"
readlink -f /nix/var/nix/profiles/system > "$state/profile.before"
sha256sum /boot/loader/loader.conf /boot/loader/entries/*.conf | sort > "$state/boot.before"
sed -i '1a\  imports = [ ./alpha-update.nix ];' "$config"
printf '%s\n' '{ ... }: { assertions = [ { assertion = false; message = "sleepy-alpha-intentional-update-failure"; } ]; }' > /etc/nixos/alpha-update.nix
if nixos-rebuild boot --flake /etc/nixos#installed > "$state/failed-update.log" 2>&1; then echo 'Invalid update unexpectedly succeeded'; exit 1; fi
grep -F sleepy-alpha-intentional-update-failure "$state/failed-update.log"
test "$(readlink -f /run/current-system)" = "$(cat "$state/generation1")"
test "$(readlink -f /nix/var/nix/profiles/system)" = "$(cat "$state/profile.before")"
sha256sum /boot/loader/loader.conf /boot/loader/entries/*.conf | sort > "$state/boot.after"
cmp "$state/boot.before" "$state/boot.after"
printf 'FAILED_UPDATE_PRESERVED_SYSTEM_AND_BOOT_OK\n'
printf '%s\n' '{ ... }: { sleepy.features.development.enable = true; environment.etc."sleepy-alpha-generation".text = "generation-2"; }' > /etc/nixos/alpha-update.nix
nixos-rebuild boot --flake /etc/nixos#installed > "$state/generation2-build.log" 2>&1
readlink -f /nix/var/nix/profiles/system > "$state/generation2"
test "$(cat "$state/generation2")" != "$(cat "$state/generation1")"
cleanup_update
trap - EXIT
printf 'SECOND_GENERATION_PREPARED_OK\n'
'''
    if phase == 'rollback':
        return user_environment + r'''
state=/var/lib/sleepy-alpha
test "$(readlink -f /run/current-system)" = "$(cat "$state/generation2")"
test "$(cat /etc/sleepy-alpha-generation)" = generation-2
printf 'SECOND_GENERATION_REAL_BOOT_OK\n'
development_user git --version
development_user direnv version
development_user sh -c 'cd "$HOME"; ! command -v python3'
# Reuse the installed system's locked nixpkgs source, without a registry lookup.
nixpkgs_source=$(timeout 60 nix eval --impure --raw --expr '(builtins.getFlake "path:/etc/nixos").inputs.nixpkgs.outPath')
case "$nixpkgs_source" in /nix/store/*-source) ;; *) exit 1;; esac
test -f "$nixpkgs_source/flake.nix"
project=/home/sleepy/Projects/sleepy-alpha-dev
test ! -e "$project"
development_user mkdir -p "$project"
development_user tee "$project/flake.nix" > /dev/null <<NIX
{
  inputs.nixpkgs.url = "path:$nixpkgs_source";
  outputs = { nixpkgs, ... }: {
    devShells.x86_64-linux.default = (import nixpkgs { system = "x86_64-linux"; }).mkShell {
      packages = [ (import nixpkgs { system = "x86_64-linux"; }).python3 ];
      shellHook = "export SLEEPY_ALPHA_DEV_SHELL=ready";
    };
  };
}
NIX
printf 'use flake\n' | development_user tee "$project/.envrc" > /dev/null
# Explicitly authorize only this fixed, user-owned disposable test project.
development_user timeout 10 direnv allow "$project"
development_user timeout 180 direnv exec "$project" bash -c 'set -e; test "$SLEEPY_ALPHA_DEV_SHELL" = ready; test "$(python3 -c "print(6 * 7)")" = 42'
development_user sh -c 'cd "$HOME"; ! command -v python3'
printf 'DEVELOPMENT_PINNED_DIRENV_PROJECT_OK\n'
nix-env --profile /nix/var/nix/profiles/system --rollback
/nix/var/nix/profiles/system/bin/switch-to-configuration boot
test "$(readlink -f /nix/var/nix/profiles/system)" = "$(cat "$state/generation1")"
printf 'PREVIOUS_GENERATION_SELECTED_FOR_BOOT_OK\n'
'''
    if phase == 'verify':
        return user_environment + r'''
test "$(readlink -f /run/current-system)" = "$(cat /var/lib/sleepy-alpha/generation1)"
test ! -e /etc/sleepy-alpha-generation
cmp /etc/nixos/configuration.nix /var/lib/sleepy-alpha/configuration.before
development_user sh -c 'cd "$HOME"; ! command -v direnv'
development_user sh -c 'cd "$HOME"; ! command -v python3'
printf 'DEVELOPMENT_REMOVED_AFTER_ROLLBACK_OK\n'
printf 'PREVIOUS_GENERATION_REAL_BOOT_OK\n'
'''
    return ''


def lock_fixture(keyboard):
    """Read-only locker protocol probe; authentication stays native/QMP-only."""
    layout = 'us' if keyboard == 'us' else 'us,' + keyboard
    script = r'''
hypr getoption input:kb_layout -j | jq -e --arg expected "__LAYOUT__" '.str == $expected'
# Reuse the interpreter already required by installed nixos-rebuild-ng.
# This diagnostic does not add Python, Git or other developer tools globally.
rebuild=$(readlink -f "$(command -v nixos-rebuild)")
read -r python_shebang < "$(dirname "$rebuild")/.nixos-rebuild-wrapped"
python=${python_shebang#\#!}
test -x "$python"
locker_state() {
  runuser -u sleepy -- "$python" -c 'import socket,sys,time
with socket.socket(socket.AF_UNIX) as peer:
 deadline=time.monotonic()+2
 peer.settimeout(2)
 peer.connect(sys.argv[1])
 peer.sendall(b"status\n")
 reply=b""
 while b"\n" not in reply:
  remaining=deadline-time.monotonic()
  if remaining <= 0 or len(reply) >= 32:
   raise RuntimeError("locker status exceeded time or frame bound")
  peer.settimeout(remaining)
  chunk=peer.recv(32-len(reply))
  if not chunk:
   raise RuntimeError("locker status closed before newline")
  reply+=chunk
 assert reply in (b"locked\n",b"unlocked\n"), repr(reply)
 print(reply.decode().strip())' "/run/user/$uid/sleepy/locker.sock"
}
printf 'LOCK_RETURN_TO_DESKTOP\n'
# VT2 is the authenticated audit console. Hyprland's keyboards become usable
# only after the runner returns to its real graphical VT and input resumes.
desktop_active=false
for attempt in $(seq 1 30); do
  if test "$(cat /sys/class/tty/tty0/active)" = tty1; then desktop_active=true; break; fi
  sleep 1
done
test "$desktop_active" = true
printf 'LOCK_GRAPHICAL_VT_READY\n'
# A long offline-registration wait may legitimately trigger the normal idle
# lock. Authenticate it first; the explicit unlocked->lock test still follows.
if test "$(locker_state)" = locked; then
  idle_layout_ready=false
  for attempt in $(seq 1 30); do
    hypr switchxkblayout all 0
    if hypr devices -j | jq -e '[.keyboards[] | select(.main) | .active_keymap] == ["English (US)"]'; then idle_layout_ready=true; break; fi
    sleep 1
  done
  test "$idle_layout_ready" = true
  printf 'IDLE_LOCK_PASSWORD_READY\n'
  idle_unlocked=false
  for attempt in $(seq 1 120); do
    if test "$(locker_state)" = unlocked; then idle_unlocked=true; break; fi
    sleep 1
  done
  test "$idle_unlocked" = true
  printf 'IDLE_LOCK_NATIVE_UNLOCK_OK\n'
fi
test "$(locker_state)" = unlocked
layout_selected=false
for attempt in $(seq 1 30); do
  hypr switchxkblayout all __GROUP__
  if hypr devices -j | jq -e '[.keyboards[] | select(.main) | .active_keymap] | length == 1 and (.[0] __LAYOUT_COMPARISON__ "English (US)")'; then layout_selected=true; break; fi
  sleep 1
done
test "$layout_selected" = true
printf 'KEYBOARD_LAYOUT_SELECTED_OK\n'
hypr dispatch exec 'sleepy-shell-ipc call sleepy lock'
locked=false
for attempt in $(seq 1 40); do
  if test "$(locker_state)" = locked; then locked=true; break; fi
  sleep 1
done
test "$locked" = true
# A fresh shell has no remembered idle-resume transition. Compositor input
# must still wake its locked display; never repair this with `dpms on`.
locked_shell_pid=$(usystem show sleepy-shell.service -P MainPID)
test "$locked_shell_pid" -gt 0
usystem kill --kill-whom=main --signal=KILL sleepy-shell.service
locked_shell_recovered=false
for attempt in $(seq 1 40); do
  next_shell_pid=$(usystem show sleepy-shell.service -P MainPID)
  if test "$next_shell_pid" -gt 0 && test "$next_shell_pid" != "$locked_shell_pid" && usystem is-active --quiet sleepy-shell.service; then locked_shell_recovered=true; break; fi
  sleep 1
done
test "$locked_shell_recovered" = true
test "$(locker_state)" = locked
hypr dispatch dpms off
hypr monitors -j | jq -e 'length > 0 and all(.[]; .dpmsStatus == false)'
printf 'LOCK_SHELL_CRASH_WAKE_READY\n'
locked_display_awake=false
for attempt in $(seq 1 30); do
  if hypr monitors -j | jq -e 'length > 0 and all(.[]; .dpmsStatus == true)'; then locked_display_awake=true; break; fi
  sleep 1
done
test "$locked_display_awake" = true
test "$(locker_state)" = locked
printf 'LOCK_SHELL_CRASH_INPUT_WAKE_OK\n'
# Reproduce keyboard removal/re-addition while the native lock owns focus.
# Guest acknowledgements require the actual kernel VT, not a sent-key assumption.
printf 'LOCK_SWITCH_TO_CONSOLE\n'
console_active=false
for attempt in $(seq 1 30); do
  if test "$(cat /sys/class/tty/tty0/active)" = tty2; then console_active=true; break; fi
  sleep 1
done
test "$console_active" = true
printf 'LOCK_CONSOLE_VT_READY\n'
desktop_active=false
for attempt in $(seq 1 30); do
  if test "$(cat /sys/class/tty/tty0/active)" = tty1; then desktop_active=true; break; fi
  sleep 1
done
test "$desktop_active" = true
printf 'LOCK_RETURNED_GRAPHICAL_VT_READY\n'
# Re-added devices can reset the group. Require the requested layout again,
# after ordinary host input wakes the graphical seat, before native password.
layout_selected=false
for attempt in $(seq 1 30); do
  hypr switchxkblayout all __GROUP__
  if hypr devices -j | jq -e '[.keyboards[] | select(.main) | .active_keymap] | length == 1 and (.[0] __LAYOUT_COMPARISON__ "English (US)")'; then layout_selected=true; break; fi
  sleep 1
done
test "$layout_selected" = true
test "$(locker_state)" = locked
printf 'LOCK_VT_ROUNDTRIP_READY\n'
printf 'LOCK_READY_FOR_REAL_PASSWORD\n'
unlocked=false
for attempt in $(seq 1 120); do
  if test "$(locker_state)" = unlocked; then unlocked=true; break; fi
  sleep 1
done
test "$unlocked" = true
hypr devices -j | jq -e '[.keyboards[] | select(.main) | .active_keymap] == ["English (US)"]'
__SWITCH_MARKER__
printf 'REAL_PASSWORD_LOCK_UNLOCK_OK\n'
'''
    return script.replace('__LAYOUT__', layout).replace('__GROUP__', '0' if keyboard == 'us' else '1').replace(
        '__SWITCH_MARKER__', '' if keyboard == 'us' else "printf 'LOCK_SCREEN_LAYOUT_SWITCH_OK\\n'").replace(
        '__LAYOUT_COMPARISON__', '==' if keyboard == 'us' else '!=')


def advance_locked_vt(qmp, report, sent):
    """Advance only guest-acknowledged locked VT transitions, once per audit."""
    transitions = (
        (b'LOCK_SHELL_CRASH_WAKE_READY', ('shift',)),
        (b'LOCK_SWITCH_TO_CONSOLE', ('ctrl', 'alt', 'f2')),
        (b'LOCK_CONSOLE_VT_READY', ('ctrl', 'alt', 'f1')),
        (b'LOCK_RETURNED_GRAPHICAL_VT_READY', ('shift',)),
    )
    for marker, keys in transitions:
        if marker not in report:
            break
        if marker not in sent:
            qmp.keys(*keys)
            sent.add(marker)


def daily_menu_focus_fixture():
    """Wait for the real graphical seat before accepting menu key input."""
    return r'''
system_menu_input_ready() {
  test "$(cat /sys/class/tty/tty0/active)" = tty1 || return 1
  if test "${system_menu_vt_announced:-false}" != true; then
    system_menu_vt_announced=true
    printf 'DAILY_SYSTEM_MENU_VT_READY\n'
  fi
  hypr devices -j | jq -e '[.keyboards[] | select(.main)] | length == 1' > /dev/null || return 1
  hypr dispatch focuswindow "address:$system_menu_address" > /dev/null || return 1
  hypr activewindow -j | jq -e --arg address "$system_menu_address" '.address == $address' > /dev/null
}
wait_daily system_menu_input_ready
printf 'DAILY_SYSTEM_MENU_READY\n'
'''


def advance_daily_menu(machine, report, sent, stage):
    """Wake the mapped menu's seat, then send Escape only after guest readback."""
    if b'DAILY_SYSTEM_MENU_MAPPED\n' not in report:
        return
    if 'system-menu-wake' not in sent:
        sent.add('system-menu-wake')
        machine.qmp.keys('ctrl', 'alt', 'f1')
    if b'DAILY_SYSTEM_MENU_VT_READY\n' not in report:
        return
    if 'system-menu-seat-wake' not in sent:
        sent.add('system-menu-seat-wake')
        machine.qmp.keys('shift')
    if b'DAILY_SYSTEM_MENU_READY\n' in report and 'system-menu' not in sent:
        sent.add('system-menu')
        machine.wait_screen(
            ('Sleepy system', 'Current and booted system', 'List recovery generations',
             'Apply the configuration', 'Return to the previous'),
            f'{stage}-system-menu', timeout=25)
        machine.qmp.keys('esc')


def flatpak_fixture(after_reboot):
    """Public Flathub registration through the installed timer, without mocks."""
    if after_reboot:
        return r'''
flatpak remotes --system --columns=name,url | grep -E '^flathub[[:space:]]+https://dl.flathub.org/repo/$'
printf 'FLATPAK_REMOTE_PERSISTED_OK\n'
'''
    return r'''
systemctl is-active multi-user.target
usystem is-active graphical-session.target
! flatpak remotes --system --columns=name | grep -Fx flathub
# NIC has been down since before guest firmware execution. Wait for the real
# registration attempt to fail, without shortening its production timeout.
registration_failed=false
for attempt in $(seq 1 60); do
  if systemctl is-failed --quiet sleepy-flathub.service; then registration_failed=true; break; fi
  sleep 1
done
test "$registration_failed" = true
systemctl is-active multi-user.target
usystem is-active graphical-session.target
printf 'FLATPAK_OFFLINE_DESKTOP_AND_FAILED_REGISTRATION_OK\n'
printf 'FLATPAK_ENABLE_NETWORK\n'
# Natural five-minute timer; never manually start/restart the service here.
registered=false
for attempt in $(seq 1 210); do
  if systemctl is-active --quiet sleepy-flathub.service && flatpak remotes --system --columns=name,url | grep -Eq '^flathub[[:space:]]+https://dl.flathub.org/repo/$'; then registered=true; break; fi
  sleep 2
done
journalctl -b -u sleepy-flathub.service --no-pager -n 30
test "$registered" = true
printf 'FLATPAK_REAL_FLATHUB_TIMER_RECOVERY_OK\n'
hypr dispatch exec gnome-software
software_open=false
for attempt in $(seq 1 30); do
  if hypr clients -j | jq -e 'any(.[]; .mapped and (.class | ascii_downcase | contains("gnome.software")))' > /dev/null; then software_open=true; break; fi
  sleep 1
done
test "$software_open" = true
printf 'FLATPAK_SOFTWARE_WINDOW_OK\n'
# Application installation is a separate manual GUI acceptance step. This
# marker asserts only the mapped Software window, not a downloaded application.
'''


def keyring_fixture(after_reboot):
    """Native Secret Service, using an explicitly nonsecret disposable sentinel."""
    script = r"""
# PAM should unlock the actual login collection; never drive an extra prompt.
test "$(uenv timeout 10 busctl --user get-property org.freedesktop.secrets /org/freedesktop/secrets/collection/login org.freedesktop.Secret.Collection Locked)" = 'b false'
keyring_load=$(uenv timeout 10 systemctl --user show gnome-keyring-daemon.service -p LoadState --value)
test "$keyring_load" != bad-setting
# libsecret is already in the installed closure, but its CLI need not be global.
# Pick the first executable from sorted, store-backed libsecret outputs.
timeout 10 nix-store --query --requisites /run/current-system > /tmp/sleepy-alpha-system-closure
secret_tool=
while IFS= read -r package; do
  case "$package" in
    /nix/store/*-libsecret-*)
      if test -x "$package/bin/secret-tool"; then secret_tool="$package/bin/secret-tool"; break; fi ;;
  esac
done < <(sort -u /tmp/sleepy-alpha-system-closure)
test -n "$secret_tool"
"""
    if not after_reboot:
        script += r"""
printf %s sleepy-disposable-keyring-regression | uenv timeout 10 "$secret_tool" store --label=Sleepy-VM-regression sleepy-alpha regression
"""
    script += r"""
# Compare in memory; do not print the stored value to guest evidence.
keyring_value=$(uenv timeout 10 "$secret_tool" lookup sleepy-alpha regression)
test "$keyring_value" = sleepy-disposable-keyring-regression
unset keyring_value
"""
    return script + ("printf 'DAILY_KEYRING_PERSISTED_UNLOCKED_OK\\n'\n" if after_reboot else
                     "printf 'DAILY_KEYRING_STORE_LOOKUP_OK\\n'\n")


def daily_fixture(after_reboot):
    """Installed default-profile assertions; invoked only by --daily-usability."""
    common = r'''
uenv() { runuser -u sleepy -- env HOME=/home/sleepy PATH="/etc/profiles/per-user/sleepy/bin:/home/sleepy/.nix-profile/bin:$PATH" XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus "$@"; }
fast_config=/home/sleepy/.config/fastfetch/config.jsonc
logo=$(jq -er '.logo.source' "$fast_config")
test -s "$logo"
case "$logo" in /nix/store/*/share/sleepy-artwork/branding/fastfetch.txt) ;; *) exit 1;; esac
grep -F 'S L E E P Y' "$logo"
uenv timeout 20 fastfetch > /tmp/sleepy-alpha-fastfetch.txt
grep -F 'S L E E P Y' /tmp/sleepy-alpha-fastfetch.txt
printf 'DAILY_FASTFETCH_ASSET_AND_EXECUTION_OK\n'
grep -F 'gtk-theme-name=adw-gtk3-dark' /home/sleepy/.config/gtk-3.0/settings.ini
grep -F 'gtk-icon-theme-name=Papirus-Dark' /home/sleepy/.config/gtk-3.0/settings.ini
# The installed system exports dconf. Query the actual user's database with
# the graphical session's data paths, not sudo's root Flatpak environment.
dconf_tool=/run/current-system/sw/bin/dconf
test -x "$dconf_tool"
session_data_dirs=$(uenv systemctl --user show-environment | sed -n 's/^XDG_DATA_DIRS=//p')
test -n "$session_data_dirs"
test "$(uenv env XDG_CONFIG_HOME=/home/sleepy/.config XDG_DATA_DIRS="$session_data_dirs" "$dconf_tool" read /org/gnome/desktop/interface/color-scheme)" = "'prefer-dark'"
printf 'DAILY_GTK_DARK_CONFIG_OK\n'
uenv timeout 5 sleepy-system status > /tmp/sleepy-alpha-system-status.txt
grep -Fx "Current system: $(readlink -e /run/current-system)" /tmp/sleepy-alpha-system-status.txt
grep -Fx "Booted system: $(readlink -e /run/booted-system)" /tmp/sleepy-alpha-system-status.txt
grep -Fx "Selected system profile: $(readlink -e /nix/var/nix/profiles/system)" /tmp/sleepy-alpha-system-status.txt
printf 'DAILY_SYSTEM_STATUS_OK\n'
# Only doctor summaries enter evidence, never raw desktop payloads.
# A structurally valid UPower DisplayDevice with no battery is Unsupported;
# Bluetooth without a running adapter service is Unavailable.
set +e
uenv timeout 5 sleepyctl doctor --json > /tmp/sleepy-alpha-doctor.json
doctor_status=$?
set -e
cat /tmp/sleepy-alpha-doctor.json
test "$doctor_status" = 0
jq -e '.ok == true
  and any(.checks[]; .capability == "audio" and .status == "available")
  and any(.checks[]; .capability == "battery" and .status == "unsupported")
  and any(.checks[]; .capability == "bluetooth" and .status == "unavailable")' /tmp/sleepy-alpha-doctor.json
printf 'DAILY_DOCTOR_HEALTHY_WITH_VIRTUAL_AUDIO_OK\n'
'''
    common += keyring_fixture(after_reboot)
    if after_reboot:
        return common + r'''
sha256sum -c /var/lib/sleepy-alpha/screenshot.sha256
printf 'DAILY_SCREENSHOT_PERSISTED_OK\n'
'''
    return common + r'''
wait_daily() {
  for attempt in $(seq 1 30); do if "$@"; then return 0; fi; sleep 1; done
  return 1
}
picker_visible() { hypr layers -j | jq -e '.. | objects | select(.namespace? == "sleepy-area-picker")' > /dev/null; }
picker_hidden() { hypr layers -j | jq -e '[.. | objects | select(.namespace? == "sleepy-area-picker")] | length == 0' > /dev/null; }
swappy_visible() { hypr clients -j | jq -e 'any(.[]; (.class | ascii_downcase | contains("swappy")) and .mapped)' > /dev/null; }
complete_png() {
  test "$(od -An -tx1 -N8 "$1" | tr -d ' \n')" = 89504e470d0a1a0a &&
    test "$(tail -c 12 "$1" | od -An -tx1 | tr -d ' \n')" = 0000000049454e44ae426082
}
# Open the actual packaged menu in a new, readable terminal; only Escape is
# sent by the host. Comparing both targets and generation listings detects any
# unintended system change without exercising rebuild/rollback during this gate.
uenv timeout 5 sleepy-system status > /tmp/sleepy-alpha-system-before-menu.txt
uenv timeout 5 sleepy-system generations > /tmp/sleepy-alpha-generations-before-menu.txt
hypr clients -j | jq '[.[] | .address]' > /tmp/sleepy-alpha-before-system-menu.json
hypr dispatch exec '[float; size 90% 90%; center] ghostty -e sleepy-system'
system_menu_visible() {
  system_menu_address=$(hypr clients -j | jq -r --slurpfile before /tmp/sleepy-alpha-before-system-menu.json '[.[] | select(.mapped and (.class | ascii_downcase | contains("ghostty")) and (.address as $a | $before[0] | index($a) | not))] | .[0].address // empty')
  test -n "$system_menu_address"
}
wait_daily system_menu_visible
printf 'DAILY_SYSTEM_MENU_MAPPED\n'
''' + daily_menu_focus_fixture() + r'''
system_menu_closed() { hypr clients -j | jq -e --arg address "$system_menu_address" 'all(.[]; .address != $address)' > /dev/null; }
wait_daily system_menu_closed
uenv timeout 5 sleepy-system status > /tmp/sleepy-alpha-system-after-menu.txt
uenv timeout 5 sleepy-system generations > /tmp/sleepy-alpha-generations-after-menu.txt
cmp /tmp/sleepy-alpha-system-before-menu.txt /tmp/sleepy-alpha-system-after-menu.txt
cmp /tmp/sleepy-alpha-generations-before-menu.txt /tmp/sleepy-alpha-generations-after-menu.txt
printf 'DAILY_SYSTEM_MENU_CANCEL_UNCHANGED_OK\n'
# The host presses Print and selects a rectangle using actual pointer input.
install -d -m 0700 /var/lib/sleepy-alpha
uenv mkdir -p /home/sleepy/Pictures/Screenshots
touch /tmp/sleepy-alpha-before-screenshot
printf 'DAILY_PRESS_PRINT\n'
wait_daily picker_visible
printf 'DAILY_SELECT_AREA\n'
wait_daily swappy_visible
printf 'DAILY_SAVE_SWAPPY\n'
last_png_hash=''
stable_new_png() {
  screenshot=$(find /home/sleepy/Pictures/Screenshots -maxdepth 1 -name '*.png' -newer /tmp/sleepy-alpha-before-screenshot -print -quit)
  test -n "$screenshot" && complete_png "$screenshot" || return 1
  current_png_hash=$(sha256sum "$screenshot") || return 1
  if test "$current_png_hash" != "$last_png_hash"; then
    last_png_hash=$current_png_hash
    return 1
  fi
}
# The PNG end chunk and two equal hashes a poll apart exclude partial saves.
wait_daily stable_new_png
printf '%s\n' "$last_png_hash" > /var/lib/sleepy-alpha/screenshot.sha256
printf 'DAILY_SCREENSHOT_SAVED_PNG_OK\n'
# Explicit graphical opening must produce a new mapped client. The screenshot records what actually rendered.
hypr clients -j | jq '[.[] | .address]' > /tmp/sleepy-alpha-before-open.json
hypr dispatch exec "xdg-open $screenshot"
viewer_visible() { hypr clients -j | jq -e --slurpfile before /tmp/sleepy-alpha-before-open.json 'any(.[]; .mapped and (.class | ascii_downcase | contains("imv")) and (.address as $a | $before[0] | index($a) | not))' > /dev/null; }
wait_daily viewer_visible
printf 'DAILY_SCREENSHOT_VIEWER_OPEN_OK\n'
wait_daily picker_hidden
wayland_display=$(uenv systemctl --user show-environment | sed -n 's/^WAYLAND_DISPLAY=//p')
test -n "$wayland_display"
# Replace any previous image with known text before the real key press. A stale
# PNG must never satisfy the clipboard screenshot acceptance marker.
printf 'sleepy-alpha-clipboard-sentinel' | uenv env WAYLAND_DISPLAY="$wayland_display" timeout 2 wl-copy --type text/plain
test "$(uenv env WAYLAND_DISPLAY="$wayland_display" timeout 2 wl-paste --type text/plain --no-newline)" = sleepy-alpha-clipboard-sentinel
clipboard_types=$(uenv env WAYLAND_DISPLAY="$wayland_display" timeout 2 wl-paste --list-types)
! printf '%s\n' "$clipboard_types" | grep -Fx image/png
printf 'DAILY_PRESS_CLIPBOARD\n'
wait_daily picker_visible
printf 'DAILY_SELECT_CLIPBOARD_AREA\n'
wait_daily picker_hidden
clipboard_png() {
  uenv env WAYLAND_DISPLAY="$wayland_display" timeout 2 wl-paste --type image/png > /tmp/sleepy-alpha-clipboard.png 2>/dev/null || return 1
  complete_png /tmp/sleepy-alpha-clipboard.png
}
wait_daily clipboard_png
printf 'DAILY_SCREENSHOT_CLIPBOARD_PNG_OK\n'
'''


def advance_daily_idle(qmp, report, sent):
    if b'DAILY_IDLE_SAMPLE_READY\n' in report and 'idle-sampling' not in sent:
        sent.add('idle-sampling')
        qmp.keys('ctrl', 'alt', 'f1')
        qmp.keys('shift')
    if ('idle-sampling' in sent and b'DAILY_IDLE_SHELL_STABLE_OK\n' in report
            and 'idle-complete' not in sent):
        sent.add('idle-complete')
        qmp.keys('ctrl', 'alt', 'f2')


def daily_idle_fixture():
    # A fixed 8 GiB, 1280px software-rendered VM normally uses well below 1 GiB
    # for the shell. 128 MiB/min leaves cache warm-up headroom while rejecting
    # the observed feedback loop (approximately 600 MiB/min). Not an OS limit.
    return r'''
printf 'DAILY_IDLE_SAMPLE_READY\n'
for attempt in $(seq 1 30); do
  test "$(cat /sys/class/tty/tty0/active)" = tty1 && break
  sleep 1
done
test "$(cat /sys/class/tty/tty0/active)" = tty1
shell_pid=$(usystem show sleepy-shell.service -P MainPID)
shell_restarts=$(usystem show sleepy-shell.service -P NRestarts)
"$python" - "$shell_pid" <<'IDLE_PY'
import json, os, pathlib, sys, time
pid = int(sys.argv[1])
assert pid > 1, "shell has no running MainPID"
base = pathlib.Path('/proc') / str(pid)
def sample():
    # comm may contain spaces or parentheses; fields start after its final ')'.
    fields = (base / 'stat').read_text().rsplit(')', 1)[1].split()
    rss = int(next(line.split()[1] for line in (base / 'status').read_text().splitlines() if line.startswith('VmRSS:')))
    return {'pid': pid, 'start_ticks': int(fields[19]), 'rss_kib': rss,
            'cpu_ticks': int(fields[11]) + int(fields[12]), 'threads': int(fields[17])}
start = time.monotonic()
first = sample()
peak = first['rss_kib']
for index in range(7):
    if index:
        time.sleep(max(0, start + index * 10 - time.monotonic()))
    current = sample()
    current['elapsed_seconds'] = round(time.monotonic() - start, 3)
    current['cpu_seconds'] = (current['cpu_ticks'] - first['cpu_ticks']) / os.sysconf('SC_CLK_TCK')
    peak = max(peak, current['rss_kib'])
    print('DAILY_IDLE_SAMPLE ' + json.dumps(current, sort_keys=True), flush=True)
    assert current['start_ticks'] == first['start_ticks'], "shell PID was reused"
    assert current['rss_kib'] <= 1024 * 1024, "shell exceeded 1 GiB resident memory"
    assert peak - first['rss_kib'] <= 128 * 1024, "shell grew over 128 MiB within one minute"
assert time.monotonic() - start >= 60
IDLE_PY
usystem is-active sleepy-shell.service
test "$(usystem show sleepy-shell.service -P MainPID)" = "$shell_pid"
test "$(usystem show sleepy-shell.service -P NRestarts)" = "$shell_restarts"
printf 'DAILY_IDLE_SHELL_STABLE_OK\n'
'''


def guest_report(machine, password, stage, after_reboot=False, update_phase=None, final=False, recovery_phase=None):
    """Authenticate on a real VT, then explicitly sudo fixed disposable-VM checks."""
    machine.qmp.keys('ctrl', 'alt', 'f2')
    machine.wait_screen('login:', f'{stage}-console')
    machine.qmp.text('sleepy\n')
    machine.wait_screen('Password:', f'{stage}-password-prompt')
    machine.qmp.text(password + '\n')
    time.sleep(3)
    machine.qmp.text("printf 'SLEEPY_AUTH_%s\\n' OK\n")
    machine.wait_screen('SLEEPY_AUTH_OK', f'{stage}-authenticated')
    channel = socket.socket(socket.AF_UNIX)
    audit_timeout = 1800 if update_phase else 180
    if getattr(machine, 'flatpak_recovery', False) and not after_reboot:
        # One production attempt (60s), natural retry (420s), Software (30s).
        audit_timeout += 510
    if getattr(machine, 'daily_usability', False):
        audit_timeout += 90  # 30s graphical VT acknowledgement + 60s idle samples.
    channel.settimeout(audit_timeout)
    channel.connect(str(machine.output / 'report.sock'))
    script = r'''#!/usr/bin/env bash
set -eu
exec > /dev/virtio-ports/org.sleepy.test 2>&1
audit_failure() {
  status=$?
  printf 'GUEST_AUDIT_ERROR line=%s command=%s status=%s\n' "$1" "$2" "$status"
  if test -f /var/lib/sleepy-alpha/generation2-build.log; then tail -n 100 /var/lib/sleepy-alpha/generation2-build.log; fi
  sync
  printf 'SLEEPY_REPORT_FAILED line=%s\n' "$1"
}
trap 'audit_failure "$LINENO" "$BASH_COMMAND"' ERR
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
test -f /home/sleepy/.local/state/sleepy/welcome-seen
test "$(stat -c %u /home/sleepy/.local/state/sleepy/welcome-seen)" = "$uid"
test "$(usystem show sleepy-welcome.service -P ActiveState)" = inactive
test "$(usystem show sleepy-welcome.service -P MainPID)" = 0
printf 'FIRST_BOOT_WELCOME_DISMISSED_AND_INACTIVE_OK\n'
''' + (r'''
test "$(usystem show sleepy-welcome.service -P ConditionResult)" = no
printf 'FIRST_BOOT_WELCOME_STATE_PERSISTED_OK\n'
''' if after_reboot else '') + r'''
hypr() { runuser -u sleepy -- env XDG_RUNTIME_DIR=/run/user/$uid hyprctl -i 0 "$@"; }
hypr dispatch exec ghostty
hypr dispatch exec thunar
apps=false
for attempt in $(seq 1 40); do
  hypr clients -j > /tmp/sleepy-alpha-clients.json
  if jq -e 'any(.[]; .class | ascii_downcase | contains("ghostty")) and any(.[]; .class | ascii_downcase | contains("thunar"))' /tmp/sleepy-alpha-clients.json > /dev/null; then apps=true; break; fi
  sleep 1
done
test "$apps" = true
printf 'TERMINAL_AND_FILE_MANAGER_WINDOWS_OK\n'
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
hypr getoption general:border_size -j | jq -e '.int == 3'
printf 'REAL_HYPRLAND_SETTING_PERSISTED_OK\n'
printf 'PERSISTENCE_AFTER_REBOOT_OK\n'
''' if after_reboot else r'''
install -d -m 0700 /var/lib/sleepy-alpha
cp -p /home/sleepy/.config/hypr/sleepy-user.conf /var/lib/sleepy-alpha/hypr-user.before
runuser -u sleepy -- sh -c 'printf "\n# Sleepy alpha integration check\ngeneral {\n border_size = 3\n}\n" >> /home/sleepy/.config/hypr/sleepy-user.conf'
hypr reload
hypr getoption general:border_size -j | jq -e '.int == 3'
printf 'REAL_HYPRLAND_SETTING_APPLIED_OK\n'
runuser -u sleepy -- mkdir -p /home/sleepy/.config/sleepy
runuser -u sleepy -- sh -c 'printf sleepy-alpha-state > /home/sleepy/.config/sleepy/alpha-persistence'
sync
printf 'PERSISTENCE_MARKER_WRITTEN\n'
''') + (flatpak_fixture(after_reboot) if getattr(machine, 'flatpak_recovery', False) else '') + lock_fixture(getattr(machine, 'keyboard', 'us')) + (daily_fixture(after_reboot) + daily_idle_fixture() if getattr(machine, 'daily_usability', False) else '') + update_fixture(update_phase) + boot_recovery.fixture(recovery_phase) + (r'''
cp -p /var/lib/sleepy-alpha/hypr-user.before /home/sleepy/.config/hypr/sleepy-user.conf
hypr reload
printf 'USER_SETTING_FIXTURE_RESTORED_OK\n'
''' if final else '') + r'''
sync
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
    daily_sent = set()
    lock_desktop_shown = False
    lock_input_sent = False
    lock_graphical_woken = False
    idle_lock_input_sent = False
    lock_returned_to_console = False
    deadline = time.monotonic() + audit_timeout
    report_file = (machine.output / f'{stage}-guest-report.txt').open('wb')
    try:
        while b'SLEEPY_REPORT_COMPLETE' not in report and b'SLEEPY_REPORT_FAILED' not in report:
            if time.monotonic() > deadline: raise RuntimeError('Guest audit did not complete')
            chunk = channel.recv(65536)
            if not chunk: break
            report += chunk
            report_file.write(chunk); report_file.flush()
            if b'LOCK_RETURN_TO_DESKTOP' in report and not lock_desktop_shown:
                machine.qmp.keys('ctrl', 'alt', 'f1')
                lock_desktop_shown = True
            if b'LOCK_GRAPHICAL_VT_READY' in report and not lock_graphical_woken:
                # The kernel VT is ready; ordinary input resumes compositor
                # keyboards and DPMS before the guest selects its keymap.
                machine.qmp.keys('shift')
                lock_graphical_woken = True
            if b'IDLE_LOCK_PASSWORD_READY' in report and not idle_lock_input_sent:
                machine.wait_screen('Password', f'{stage}-idle-locked', timeout=30)
                # Guest confirmed US for this preparatory native unlock.
                machine.qmp.text(password + '\n')
                idle_lock_input_sent = True
            advance_locked_vt(machine.qmp, report, daily_sent)
            if b'LOCK_READY_FOR_REAL_PASSWORD' in report and not lock_input_sent:
                machine.wait_screen('Password', f'{stage}-locked')
                if getattr(machine, 'keyboard', 'us') != 'us':
                    machine.qmp.keys('alt', 'shift')
                machine.qmp.text(password + '\n')
                lock_input_sent = True
            if b'REAL_PASSWORD_LOCK_UNLOCK_OK' in report and not lock_returned_to_console:
                machine.screen(f'{stage}-unlocked')
                machine.qmp.keys('ctrl', 'alt', 'f2')
                lock_returned_to_console = True
            if b'FLATPAK_ENABLE_NETWORK' in report and 'network-enabled' not in daily_sent:
                daily_sent.add('network-enabled')
                machine.qmp.call('set_link', name='nic0', up=True)
            if b'FLATPAK_SOFTWARE_WINDOW_OK' in report and 'software-shown' not in daily_sent:
                daily_sent.add('software-shown')
                machine.qmp.keys('ctrl', 'alt', 'f1')
                machine.qmp.keys('shift')
                time.sleep(2)
                machine.screen(f'{stage}-software')
            if getattr(machine, 'daily_usability', False):
                advance_daily_menu(machine, report, daily_sent, stage)
                for marker, action in [
                    (b'DAILY_PRESS_PRINT', 'print'),
                    (b'DAILY_SELECT_AREA', 'select'),
                    (b'DAILY_SAVE_SWAPPY', 'save'),
                    (b'DAILY_PRESS_CLIPBOARD', 'clipboard'),
                    (b'DAILY_SELECT_CLIPBOARD_AREA', 'select-clipboard'),
                ]:
                    if marker not in report or marker in daily_sent: continue
                    daily_sent.add(marker)
                    machine.qmp.keys('ctrl', 'alt', 'f1')
                    time.sleep(1)
                    machine.screen(f'{stage}-{action}-before')
                    if action in ('print', 'clipboard'):
                        if action == 'clipboard': machine.qmp.keys('shift', 'print')
                        else: machine.qmp.keys('print')
                    elif action == 'save':
                        machine.qmp.keys('ctrl', 's')
                    else:
                        for x, y, down in [(10000, 10000, True), (23000, 23000, False)]:
                            machine.qmp.call('input-send-event', events=[
                                {'type': 'abs', 'data': {'axis': 'x', 'value': x}},
                                {'type': 'abs', 'data': {'axis': 'y', 'value': y}},
                                {'type': 'btn', 'data': {'button': 'left', 'down': down}},
                            ])
                            time.sleep(.3)
                if b'DAILY_SCREENSHOT_CLIPBOARD_PNG_OK' in report and 'finished' not in daily_sent:
                    daily_sent.add('finished')
                    machine.screen(f'{stage}-daily-screenshot-viewer')
            # Coalesced unlock/UI markers may return to VT2; idle acknowledgement
            # must run last so the new sampling phase remains on the desktop.
            advance_daily_idle(machine.qmp, report, daily_sent)
            if len(report) > 1024 * 1024: raise RuntimeError('Guest audit exceeded 1 MiB output bound')
    finally:
        channel.close()
        report_file.close()
    if b'SLEEPY_REPORT_COMPLETE' not in report:
        raise RuntimeError(f'Installed guest audit failed; inspect {stage}-guest-report.txt')
    machine.qmp.text('exit\n')
    machine.qmp.keys('ctrl', 'alt', 'f1')
    time.sleep(3)
    machine.screen(f'{stage}-applications')
    return report.decode(errors='replace')


def login_desktop(machine, password, name):
    machine.wait_screen(('Welcome back', 'User:', 'Session:'), f'{name}-greeter', timeout=300)
    if getattr(machine, 'pause_at_greeter', False):
        continuation = machine.output / 'continue-greeter'
        machine.qmp.close()
        print(f'Paused before graphical input. Inspect {name}-greeter.png; QMP socket is released for manual inspection. '
              f'After selecting the user and focusing the password field, close your QMP client and create {continuation}.', flush=True)
        deadline = time.monotonic() + 1800
        while not continuation.is_file():
            if time.monotonic() > deadline: raise RuntimeError('Manual greeter inspection timed out')
            if machine.process.poll() is not None: raise RuntimeError('VM exited during greeter inspection')
            time.sleep(1)
        machine.qmp = QMP(machine.output / 'qmp.sock')
        continuation.unlink()
        machine.pause_at_greeter = False
    else:
        machine.qmp.keys('ret')
    machine.wait_screen('Password', f'{name}-greeter-password')
    machine.qmp.text(password + '\n')
    time.sleep(20)
    machine.screen(f'{name}-desktop')
    if name == 'installed':
        machine.wait_screen('Welcome to Sleepy', f'{name}-welcome')
        machine.qmp.keys('ret')
        time.sleep(3)
        machine.screen(f'{name}-welcome-dismissed')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--iso', required=True, type=Path)
    parser.add_argument('--image-source-revision', help='Source commit recorded by the ISO build (separate from runner checkout revision)')
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--firmware', type=Path, default=Path('/usr/share/edk2/x64/OVMF_CODE.4m.fd'))
    parser.add_argument('--vars', type=Path, default=Path('/usr/share/edk2/x64/OVMF_VARS.4m.fd'))
    parser.add_argument('--memory', type=int, default=8192)
    parser.add_argument('--install-timeout', type=int, default=10800)
    parser.add_argument('--interrupt-install', action='store_true', help='Before visible TUI installation, interrupt a real disposable-disk install after mounting and verify cleanup')
    parser.add_argument('--keyboard', choices=('us', 'ru', 'de', 'cz'), default='us', help='Select the installed keyboard through the real TUI and test lock-screen switching')
    parser.add_argument('--flatpak-recovery', action='store_true', help='Select Flatpak in TUI; prove offline first desktop and real Flathub timer recovery, then launch Software')
    parser.add_argument('--daily-usability', action='store_true', help='Verify installed daily defaults, real Print save/clipboard and PNG persistence; adds virtual audio')
    parser.add_argument('--boot-recovery', action='store_true', help='Damage only disposable ESP entries, prove failed boot, repair through the real ISO TUI and verify unchanged system/user data')
    parser.add_argument('--update-safety', action='store_true', help='Also test failed rebuild boot safety, boot a second generation, then rollback and boot the original')
    parser.add_argument('--pause-at-greeter', action='store_true', help='Pause and release QMP before first graphical login for field inspection; see printed continuation instructions')
    parser.add_argument('--cache-url', help='Optional signed binary cache reachable inside VM (e.g. http://10.0.2.2:8080)')
    parser.add_argument('--cache-public-key', help='Public signing key for the optional cache; private key must stay on host')
    args = parser.parse_args()
    if args.boot_recovery and args.update_safety:
        parser.error('--boot-recovery and --update-safety are separate destructive-fixture scenarios')
    output, iso = args.output.resolve(), args.iso.resolve()
    if bool(args.cache_url) != bool(args.cache_public_key): parser.error('--cache-url and --cache-public-key must be supplied together')
    if args.cache_url and not re.fullmatch(r'https?://[A-Za-z0-9.:/_-]+', args.cache_url): parser.error('Invalid cache URL')
    if args.cache_public_key and not re.fullmatch(r'[A-Za-z0-9._-]+:[A-Za-z0-9+/]+=*', args.cache_public_key): parser.error('Invalid public signing key')
    if any(',' in str(path) or '\n' in str(path) for path in (output, iso, args.firmware, args.vars)):
        parser.error('QEMU artifact paths must not contain commas or line breaks')
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
              'acceleration': acceleration, 'cache_transport': args.cache_url, 'cache_public_key': args.cache_public_key, 'image_source_revision': args.image_source_revision, 'completed': [], 'runner_source_revision': subprocess.run(
                  ['git', 'rev-parse', 'HEAD'], capture_output=True, text=True).stdout.strip(),
              'runner_source_dirty': bool(subprocess.run(['git', 'status', '--porcelain'], capture_output=True, text=True).stdout)}
    machine = Machine(output, args.firmware.resolve(), args.memory, acceleration)
    machine.pause_at_greeter = args.pause_at_greeter
    machine.keyboard = args.keyboard
    machine.daily_usability = args.daily_usability
    machine.flatpak_recovery = args.flatpak_recovery
    result['flatpak_recovery'] = args.flatpak_recovery
    result['daily_usability'] = args.daily_usability
    result['keyboard'] = args.keyboard
    result['boot_recovery'] = args.boot_recovery
    try:
        print('Booting installer and driving the visible tty1 TUI.', flush=True)
        machine.boot('installer', iso)
        install(machine, password, args.install_timeout, args.cache_url, args.cache_public_key, args.interrupt_install, args.keyboard)
        result['completed'] += getattr(machine, 'safety_completed', [])
        result['completed'].append('tui-install-and-shutdown')
        machine.stop()
        print('Booting installed disk without installer media.', flush=True)
        machine.boot('installed')
        login_desktop(machine, password, 'installed')
        guest_report(machine, password, 'installed', update_phase='seed' if args.update_safety else None,
                     recovery_phase='damage' if args.boot_recovery else None)
        result['completed'] += ['installed-disk-boot', 'real-password-login', 'desktop-units-and-socket',
                                'shell-SIGKILL-recovery', 'session-daemon-SIGKILL-recovery', 'terminal-and-file-manager-windows', 'real-Hyprland-setting-applied']
        if args.update_safety:
            result['completed'] += ['failed-update-preserved-boot', 'second-generation-prepared']
            machine.qmp.call('system_powerdown')
            machine.process.wait(timeout=120)
            machine.stop()
            machine.boot('generation2')
            login_desktop(machine, password, 'generation2')
            guest_report(machine, password, 'generation2', after_reboot=True, update_phase='rollback')
            result['completed'] += ['second-generation-real-boot', 'previous-generation-selected']
        # An ACPI shutdown exercises normal system cleanup before the next boot.
        machine.qmp.call('system_powerdown')
        machine.process.wait(timeout=120)
        machine.stop()
        if args.boot_recovery:
            result['completed'].append('disposable-ESP-entries-removed-after-authentication')
            boot_recovery.repair(machine, iso, serial_line, SHELL_PROMPT)
            result['completed'] += ['damaged-disk-no-entry-boot', 'recovery-inspect-cancel-partitions-unchanged', 'recovery-busy-target-rejected',
                                    'real-TUI-boot-repair-and-shutdown']
        machine.boot('offline-reboot')
        machine.qmp.call('set_link', name='nic0', up=False)
        login_desktop(machine, password, 'offline-reboot')
        guest_report(machine, password, 'offline-reboot', after_reboot=True,
                     update_phase='verify' if args.update_safety else None, final=True,
                     recovery_phase='verify' if args.boot_recovery else None)
        result['completed'] += ['offline-disk-reboot', 'offline-password-login', 'user-state-persistence', 'real-Hyprland-setting-persistence']
        if args.update_safety: result['completed'].append('previous-generation-real-boot')
        if args.boot_recovery: result['completed'].append('repaired-disk-password-login-profile-userdata-preserved')
        machine.qmp.call('system_powerdown')
        machine.process.wait(timeout=120)
        result['completed'].append('clean-final-shutdown')
        result['status'] = 'passed'
    except (Exception, KeyboardInterrupt) as error:
        result['status'] = 'interrupted' if isinstance(error, KeyboardInterrupt) else 'failed'
        result['error'] = 'Runner interrupted by operator' if isinstance(error, KeyboardInterrupt) else str(error)
        if machine.process is not None and machine.process.poll() is None:
            try: machine.screen('failure')
            except Exception: pass
            # Give the installed filesystem time to commit diagnostics before a
            # forced QMP quit. Serial must be drained so a full console socket
            # cannot stall shutdown logging.
            try:
                machine.qmp.call('system_powerdown')
                serial = socket.socket(socket.AF_UNIX)
                serial.settimeout(1)
                serial.connect(str(output / 'serial.sock'))
                deadline = time.monotonic() + 60
                while machine.process.poll() is None and time.monotonic() < deadline:
                    try: serial.recv(65536)
                    except socket.timeout: pass
                serial.close()
            except (OSError, RuntimeError): pass
        print(f'VM check stopped: {result["error"]}', file=sys.stderr)
    finally:
        for check in getattr(machine, 'safety_completed', []):
            if check not in result['completed']: result['completed'].append(check)
        # Preserve verified substeps even if a later update or reboot gate fails.
        markers = {
            'IDLE_LOCK_NATIVE_UNLOCK_OK': 'preexisting-idle-lock-native-password-unlock',
            'FLATPAK_OFFLINE_DESKTOP_AND_FAILED_REGISTRATION_OK': 'flatpak-offline-first-desktop',
            'FLATPAK_REAL_FLATHUB_TIMER_RECOVERY_OK': 'flatpak-real-Flathub-timer-recovery',
            'FLATPAK_SOFTWARE_WINDOW_OK': 'flatpak-Software-window',
            'FLATPAK_REMOTE_PERSISTED_OK': 'flatpak-remote-persistence',
            **{f'DAILY_{key}_OK': value for key, value in {
                'FASTFETCH_ASSET_AND_EXECUTION': 'daily-fastfetch',
                'GTK_DARK_CONFIG': 'daily-gtk-dark-config',
                'SYSTEM_STATUS': 'daily-system-status',
                'KEYRING_STORE_LOOKUP': 'daily-keyring-store-lookup',
                'KEYRING_PERSISTED_UNLOCKED': 'daily-keyring-persisted-unlocked',
                'SYSTEM_MENU_CANCEL_UNCHANGED': 'daily-system-menu-cancel-unchanged',
                'DOCTOR_HEALTHY_WITH_VIRTUAL_AUDIO': 'daily-doctor-with-virtual-audio',
                'SCREENSHOT_SAVED_PNG': 'daily-Print-saved-PNG',
                'SCREENSHOT_VIEWER_OPEN': 'daily-screenshot-viewer-open',
                'SCREENSHOT_CLIPBOARD_PNG': 'daily-ShiftPrint-clipboard-PNG',
                'SCREENSHOT_PERSISTED': 'daily-screenshot-persistence',
                'IDLE_SHELL_STABLE': 'daily-idle-shell-memory-and-process-stability',
            }.items()},
            'LOCK_SHELL_CRASH_INPUT_WAKE_OK': 'locked-shell-SIGKILL-input-DPMS-wake',
            'LOCK_VT_ROUNDTRIP_READY': 'locked-VT-roundtrip-keyboard-restored',
            'REAL_PASSWORD_LOCK_UNLOCK_OK': 'real-password-lock-unlock',
            'LOCK_SCREEN_LAYOUT_SWITCH_OK': 'lock-screen-layout-switch',
            'REAL_USER_LOGIN_OK': 'real-password-login',
            'FIRST_BOOT_WELCOME_DISMISSED_AND_INACTIVE_OK': 'first-boot-welcome-dismissed',
            'FIRST_BOOT_WELCOME_STATE_PERSISTED_OK': 'first-boot-welcome-state-persistence',
            'INSTALLED_DISK_BOOT_OK': 'installed-disk-boot',
            'DESKTOP_UNITS_AND_SOCKET_OK': 'desktop-units-and-socket',
            'TERMINAL_AND_FILE_MANAGER_WINDOWS_OK': 'terminal-and-file-manager-windows',
            'CRASH_RECOVERY_OK sleepy-shell.service': 'shell-SIGKILL-recovery',
            'CRASH_RECOVERY_OK sleepy-session.service': 'session-daemon-SIGKILL-recovery',
            'REAL_HYPRLAND_SETTING_APPLIED_OK': 'real-Hyprland-setting-applied',
            'FAILED_UPDATE_PRESERVED_SYSTEM_AND_BOOT_OK': 'failed-update-preserved-boot',
            'DEVELOPMENT_ABSENT_IN_BASE_GENERATION_OK': 'development-disabled-base-generation',
            'DEVELOPMENT_PINNED_DIRENV_PROJECT_OK': 'development-pinned-direnv-project',
            'DEVELOPMENT_REMOVED_AFTER_ROLLBACK_OK': 'development-removed-after-rollback',
            'SECOND_GENERATION_PREPARED_OK': 'second-generation-prepared',
            'SECOND_GENERATION_REAL_BOOT_OK': 'second-generation-real-boot',
            'PREVIOUS_GENERATION_SELECTED_FOR_BOOT_OK': 'previous-generation-selected',
            'PREVIOUS_GENERATION_REAL_BOOT_OK': 'previous-generation-real-boot',
            'PERSISTENCE_AFTER_REBOOT_OK': 'user-state-persistence',
            'REAL_HYPRLAND_SETTING_PERSISTED_OK': 'real-Hyprland-setting-persistence',
        }
        for report_path in output.glob('*-guest-report.txt'):
            lines = set(report_path.read_text().splitlines())
            for marker, check in markers.items():
                if marker in lines and check not in result['completed']:
                    result['completed'].append(check)
        machine.stop()
        (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
    print(f'Result and evidence: {output}', flush=True)
    return 0 if result['status'] == 'passed' else 1


if __name__ == '__main__':
    sys.exit(main())
