#!/usr/bin/env python3
"""Sleepy whole-disk installer. Discovery/plan are read-only; execution is explicit."""
import argparse
import curses
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import selectors
import time
import subprocess
import tempfile
import pwd
import textwrap
import sys
from dataclasses import dataclass, field

PACKAGES = {
    'Development': {'git': 'Git / version control', 'vscode': 'Visual Studio Code', 'python3': 'Python', 'nodejs': 'Node.js', 'rustup': 'Rust toolchain'},
    'Games': {'steam': 'Steam', 'lutris': 'Lutris', 'prismlauncher': 'Prism Launcher / Minecraft', 'mangohud': 'MangoHud / performance overlay'},
    'Apps': {'firefox': 'Firefox', 'chromium': 'Chromium', 'vlc': 'VLC media player', 'libreoffice-fresh': 'LibreOffice', 'gimp': 'GIMP', 'keepassxc': 'KeePassXC'},
}
ALLOWLIST = {key for group in PACKAGES.values() for key in group}
GPU_CHOICES = ['auto', 'intel', 'amd', 'nvidia']
KEYBOARDS = ['us', 'gb', 'de', 'fr', 'cz', 'es', 'it', 'pl', 'ru']
RESERVED_USERS = {'root', 'nobody', 'nixbld', 'messagebus', 'dbus', 'polkituser', 'rtkit', 'avahi', 'sshd', 'cups', 'geoclue', 'nm-openvpn', 'nm-openconnect', 'sddm', 'gdm', 'lightdm', 'greetd', 'systemd-network', 'systemd-resolve', 'systemd-timesync', 'systemd-coredump', 'systemd-oom', 'dnsmasq', 'chrony', 'ntp', 'mysql', 'postgres', 'redis', 'nginx', 'wwwrun', 'nscd', 'dhcpcd', 'unbound', 'rpcbind', 'ftp', 'uucp', 'daemon', 'bin', 'mail', 'nix-serve', 'colord', 'pulse', 'pipewire'}
TIMEZONES = ['UTC', 'Europe/Prague', 'Europe/London', 'Europe/Berlin', 'America/New_York', 'America/Los_Angeles', 'Asia/Tokyo', 'Asia/Kolkata', 'Australia/Sydney']

class InstallError(Exception):
    pass


def scan_disks():
    result = subprocess.run(['lsblk', '--json', '--bytes', '--paths', '--output',
        'NAME,TYPE,SIZE,MODEL,SERIAL,WWN,MAJ:MIN,RO,MOUNTPOINTS'], check=True, capture_output=True, text=True)
    return json.loads(result.stdout)['blockdevices']


def descendants(disk):
    yield disk
    for child in disk.get('children', []):
        yield from descendants(child)


def unsafe_reason(disk):
    if disk.get('type') != 'disk' or not re.fullmatch(r'/dev/[a-zA-Z0-9_-]+', disk.get('name', '')):
        return 'Not a whole disk'
    if any(node.get('ro') for node in descendants(disk)):
        return 'Read-only media'
    if any(any(p for p in (node.get('mountpoints') or [])) for node in descendants(disk)):
        return 'Mounted filesystem or active swap (includes installation media)'
    if int(disk.get('size', 0)) < 32 * 1024**3:
        return 'At least 32 GiB required'
    if not (disk.get('serial') or disk.get('wwn')):
        return 'No stable serial/WWN; refusing ambiguous disk identity'
    return None


def disk_by_id(disk, directory='/dev/disk/by-id'):
    """Choose an existing whole-disk symlink; never synthesize IDs from a serial."""
    candidates = []
    try:
        entries = Path(directory).iterdir()
        for entry in entries:
            try:
                if entry.is_symlink() and not re.search(r'-part[0-9]+$', entry.name) and str(entry.resolve(strict=True)) == disk['name']:
                    candidates.append(entry)
            except OSError:
                continue
    except OSError:
        return ''
    candidates.sort(key=lambda p: (not p.name.startswith('wwn-'), p.name))
    return str(candidates[0]) if candidates else ''


def fingerprint(disk):
    return hashlib.sha256(json.dumps(disk, sort_keys=True).encode()).hexdigest()


def field_error(field, value):
    if field == 'hostname' and not re.fullmatch(r'[a-z](?:[a-z0-9-]{0,61}[a-z0-9])?', value):
        return 'Use 1-63 lowercase letters, digits or hyphens; start with a letter and end with a letter or digit.'
    if field == 'username' and (not re.fullmatch(r'[a-z][a-z0-9_-]{0,30}', value) or value in RESERVED_USERS or value.startswith(('nixbld', 'systemd-')) or value in {entry.pw_name for entry in pwd.getpwall() if entry.pw_uid < 1000}):
        return 'Use a lowercase account name, up to 31 characters; system account names are reserved.'
    if field == 'password' and (len(value) < 8 or any(c in value for c in '\n\r\x00:')):
        return 'Use at least 8 characters, without a colon or line separator.'
    return None


def prime_devices(pci):
    """Return one unambiguous supported NVIDIA/iGPU pair, with decimal Xorg bus IDs."""
    devices = []
    for line in pci.splitlines():
        parts = line.split()
        if len(parts) < 3 or parts[1].rstrip(':') not in ('0300', '0302', '0380'):
            continue
        match = re.fullmatch(r'([0-9a-fA-F]{4}):([0-9a-fA-F]{2}):([0-9a-fA-F]{2})\.([0-7])', parts[0])
        if not match or int(match[1], 16) != 0:
            return None  # Nonzero PCI domains need explicit expert configuration.
        busid = 'PCI:%d:%d:%d' % tuple(int(match[i], 16) for i in (2, 3, 4))
        devices.append((parts[2].split(':')[0].lower(), busid))
    nvidia = [bus for vendor, bus in devices if vendor == '10de']
    integrated = [(vendor, bus) for vendor, bus in devices if vendor in ('8086', '1002')]
    if len(devices) != 2 or len(nvidia) != 1 or len(integrated) != 1:
        return None
    return {'nvidiaBusId': nvidia[0], 'intelBusId' if integrated[0][0] == '8086' else 'amdgpuBusId': integrated[0][1]}


def detect_prime():
    try:
        pci = subprocess.run(['lspci', '-Dn'], check=True, capture_output=True, text=True).stdout
        return prime_devices(pci)
    except (OSError, subprocess.CalledProcessError):
        return None


def detected_gpu():
    try:
        pci = subprocess.run(['lspci', '-Dn'], check=True, capture_output=True, text=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return 'auto', 'GPU discovery unavailable; choose a driver manually.'
    vendors = {line.split()[2].split(':')[0] for line in pci.splitlines()
               if len(line.split()) > 2 and line.split()[1].rstrip(':') in ('0300', '0302', '0380')}
    names = {'8086': 'intel', '1002': 'amd', '10de': 'nvidia'}
    known = vendors.intersection(names)
    if len(known) > 1:
        return 'auto', 'Hybrid GPU detected. Choose NVIDIA to configure PRIME offload; auto keeps the generic graphics stack.'
    choice = names[next(iter(known))] if len(known) == 1 else 'auto'
    return choice, f'Detected graphics: {choice}. You can override this choice.'


@dataclass
class Plan:
    disk: dict
    firmware: str = 'uefi'
    boot_device: str = ''
    hostname: str = 'sleepy'
    username: str = 'sleepy'
    timezone: str = 'UTC'
    keyboard: str = 'us'
    gpu: str = 'auto'
    packages: list = field(default_factory=lambda: ['firefox'])
    nvidia_open: bool = False
    nvidia_mode: str = 'dedicated'
    prime: dict = field(default_factory=dict)

    def validate(self):
        reason = unsafe_reason(self.disk)
        if reason:
            raise InstallError(reason)
        if self.firmware not in ('uefi', 'bios'):
            raise InstallError('Invalid boot mode')
        if self.boot_device and (not re.fullmatch(r'/dev/disk/by-id/[A-Za-z0-9_.:+-]+', self.boot_device) or re.search(r'-part[0-9]+$', self.boot_device)):
            raise InstallError('Bootloader target must be an existing whole-disk /dev/disk/by-id identifier.')
        if self.firmware == 'bios' and not self.boot_device:
            raise InstallError('BIOS installation needs a stable /dev/disk/by-id identifier for the selected disk.')
        for name in ('hostname', 'username'):
            error = field_error(name, getattr(self, name))
            if error:
                raise InstallError(error)
        if not isinstance(self.nvidia_open, bool) or self.nvidia_mode not in ('dedicated', 'offload'):
            raise InstallError('Invalid NVIDIA driver selection')
        if self.nvidia_mode == 'offload':
            keys = set(self.prime)
            if self.gpu != 'nvidia' or keys not in ({'nvidiaBusId', 'intelBusId'}, {'nvidiaBusId', 'amdgpuBusId'}):
                raise InstallError('PRIME offload needs one NVIDIA device and exactly one integrated GPU.')
        if self.prime and self.nvidia_mode != 'offload':
            raise InstallError('PRIME device IDs are only valid in offload mode.')
        for key, value in self.prime.items():
            if key not in ('nvidiaBusId', 'intelBusId', 'amdgpuBusId') or not re.fullmatch(r'PCI:[0-9]{1,3}:[0-9]{1,2}:[0-7]', value):
                raise InstallError('Invalid PRIME device address')
        if self.timezone not in TIMEZONES or self.keyboard not in KEYBOARDS or self.gpu not in GPU_CHOICES:
            raise InstallError('Invalid locale or hardware selection')
        if not set(self.packages) <= ALLOWLIST:
            raise InstallError('Unknown package selection')

    def manifest(self):
        self.validate()
        return {'schema': 1, 'disk': self.disk['name'], 'serial': self.disk.get('serial'),
                'diskFingerprint': fingerprint(self.disk), 'firmware': self.firmware, 'bootDevice': self.boot_device,
                'hostname': self.hostname, 'username': self.username, 'timezone': self.timezone,
                'keyboard': self.keyboard, 'gpu': self.gpu, 'packages': sorted(self.packages),
                'nvidiaOpen': self.nvidia_open, 'nvidiaMode': self.nvidia_mode, 'prime': self.prime,
                'storage': 'ERASE ENTIRE DISK / GPT / ext4 / unencrypted / no swap'}


def nvidia_config(plan):
    if plan.gpu != 'nvidia':
        return ''
    lines = ['sleepy.hardware.nvidia.open = ' + str(plan.nvidia_open).lower() + ';',
             'sleepy.hardware.nvidia.mode = ' + json.dumps(plan.nvidia_mode) + ';']
    lines.extend('sleepy.hardware.nvidia.' + key + ' = ' + json.dumps(value) + ';' for key, value in sorted(plan.prime.items()))
    return '\n  '.join(lines)


def config_text(plan):
    plan.validate()
    quote = json.dumps
    layout = 'us,ru' if plan.keyboard == 'ru' else plan.keyboard
    layout_options = 'grp:alt_shift_toggle' if plan.keyboard == 'ru' else ''
    boot = ('boot.loader.systemd-boot.enable = true;\n  boot.loader.efi.canTouchEfiVariables = true;'
            if plan.firmware == 'uefi' else
            f'boot.loader.grub.enable = true;\n  boot.loader.grub.device = {quote(plan.boot_device)};')
    return '''{ lib, pkgs, ... }: {
  %s
  time.timeZone = %s;
  services.xserver.xkb.layout = lib.mkForce %s;
  services.xserver.xkb.options = lib.mkForce %s;
  console.keyMap = %s;
  sleepy.hardware.gpu = %s;
  %s
  users.users.root.hashedPassword = lib.mkForce "!";
  nixpkgs.config.allowUnfree = true;
  environment.systemPackages = with pkgs; [ %s ];
  programs.steam.enable = %s;
  environment.etc."snug/system.json" = {
    mode = "0644";
    text = builtins.toJSON { flake = "/etc/nixos"; host = %s; input = "sleepy"; source = "github:sleepylinux/sleepy"; };
  };
  home-manager.users.%s = {
    wayland.windowManager.hyprland.settings.input = {
      kb_layout = lib.mkForce %s;
      kb_options = lib.mkForce %s;
    };
    programs.firefox.enable = lib.mkForce %s;
  };
  system.stateVersion = "26.05";
}
''' % (boot, quote(plan.timezone), quote(layout), quote(layout_options), quote({'us': 'us', 'gb': 'uk', 'cz': 'cz', 'fr': 'fr'}.get(plan.keyboard, plan.keyboard)), quote(plan.gpu), nvidia_config(plan), ' '.join(sorted(plan.packages)), str('steam' in plan.packages).lower(), quote(plan.hostname), plan.username, quote(layout), quote(layout_options), str('firefox' in plan.packages).lower())


def flake_text(plan):
    plan.validate()
    return '''{
  description = "Sleepy Linux installed host";
  inputs.sleepy.url = "github:sleepylinux/sleepy";
  outputs = { sleepy, ... }: {
    nixosConfigurations.%s = sleepy.lib.mkSleepyHost {
      system = "x86_64-linux";
      hostName = "%s";
      primaryUser = "%s";
      hardwareModule = ./hardware-configuration.nix;
      extraModules = [ ./configuration.nix { system.extraDependencies = [ sleepy.outPath ]; } ];
    };
  };
}
''' % (plan.hostname, plan.hostname, plan.username)


class Runner:
    def __init__(self, progress=lambda message: None):
        self.progress = progress

    def run(self, argv, secret=None):
        self.progress(' '.join(argv))
        # Password input is never printed, persisted or put in argv. Output of secret commands is discarded.
        try:
            if secret is not None:
                result = subprocess.run(argv, input=secret, text=True, stdout=subprocess.DEVNULL,
                                        stderr=subprocess.DEVNULL, timeout=120)
                if result.returncode:
                    raise InstallError(f'Command failed ({result.returncode}): {argv[0]}')
                return ''
            with subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                  stderr=subprocess.STDOUT) as process:
                output = ''
                start = time.monotonic()
                try:
                    with selectors.DefaultSelector() as selector:
                        selector.register(process.stdout, selectors.EVENT_READ)
                        while selector.get_map():
                            if time.monotonic() - start > 7200:
                                raise InstallError(f'Command timed out: {argv[0]}')
                            for key, _ in selector.select(timeout=0.5):
                                chunk = os.read(key.fileobj.fileno(), 4096)
                                if not chunk:
                                    selector.unregister(key.fileobj)
                                    continue
                                output = (output + chunk.decode(errors='replace'))[-12000:]
                                lines = output.splitlines()
                                if lines:
                                    self.progress(lines[-1][-300:])
                        code = process.wait(timeout=10)
                    if code:
                        raise InstallError(f'Command failed ({code}): {argv[0]}\n{output[-3000:]}')
                    return output
                except BaseException:
                    process.kill()
                    process.wait()
                    raise
        except (OSError, subprocess.TimeoutExpired) as error:
            raise InstallError(f'Command could not finish: {argv[0]}') from error



def partition_path(disk, number):
    return disk + ('p' if disk[-1].isdigit() else '') + str(number)


def preflight(plan, source, runner):
    """Evaluate the complete selected configuration before changing any disk.

    Placeholder filesystems satisfy boot assertions; actual UUIDs and hardware
    modules are discovered after formatting. This checks evaluation, not a build.
    """
    with tempfile.TemporaryDirectory(prefix='sleepy-preflight-') as temporary:
        directory = Path(temporary)
        (directory / 'flake.nix').write_text(flake_text(plan))
        (directory / 'configuration.nix').write_text(config_text(plan))
        hardware = '{ fileSystems."/" = { device = "/dev/disk/by-label/SLEEPY-PREFLIGHT"; fsType = "ext4"; };'
        if plan.firmware == 'uefi':
            hardware += ' fileSystems."/boot" = { device = "/dev/disk/by-label/SLEEPY-EFI-PREFLIGHT"; fsType = "vfat"; };'
        (directory / 'hardware-configuration.nix').write_text(hardware + ' }\n')
        lock = directory / 'flake.lock'
        runner.progress('Checking your complete configuration before erasing the disk...')
        runner.run(['nix', '--extra-experimental-features', 'nix-command flakes', 'flake', 'lock',
                    '--override-input', 'sleepy', 'path:' + str(Path(source).resolve()),
                    '--output-lock-file', str(lock), str(directory)])
        runner.run(['nix', '--extra-experimental-features', 'nix-command flakes', 'eval',
                    str(directory) + '#nixosConfigurations.' + plan.hostname + '.config.system.build.toplevel.drvPath',
                    '--raw', '--no-update-lock-file'])
        return lock.read_text()


def execute(plan, password, confirmation, source, runner=None, scanner=scan_disks, target='/mnt', boot_resolver=os.path.realpath):
    plan.validate()
    if len(password) < 8 or any(c in password for c in '\n\r\x00:'):
        raise InstallError('Password must be at least 8 characters, without colon or control line separators.')
    if confirmation != 'ERASE ' + plan.disk['name']:
        raise InstallError('Disk confirmation does not match')
    source = Path(source)
    if not source.is_dir() or not (source / 'flake.nix').is_file() or not (source / 'flake.lock').is_file():
        raise InstallError('Bundled Sleepy source or lock is missing')
    if Path(target).is_mount() or (Path(target).exists() and any(Path(target).iterdir())):
        raise InstallError('Installation mount directory must be empty and unmounted')
    current = next((disk for disk in scanner() if disk.get('name') == plan.disk['name']), None)
    if current is None or unsafe_reason(current) or fingerprint(current) != fingerprint(plan.disk):
        raise InstallError('Disk changed since review. Rescan and confirm a new plan.')
    if plan.boot_device and boot_resolver(plan.boot_device) != plan.disk['name']:
        raise InstallError('Stable boot disk identifier no longer resolves to the reviewed disk.')
    runner = runner or Runner()
    lock_content = preflight(plan, source, runner)
    # Evaluation can fetch inputs and take time. Invalidate confirmation if the
    # disk changed during that interval; this is the last probe before mutation.
    current = next((disk for disk in scanner() if disk.get('name') == plan.disk['name']), None)
    if current is None or unsafe_reason(current) or fingerprint(current) != fingerprint(plan.disk):
        raise InstallError('Disk changed during preflight. Rescan and confirm a new plan.')
    if plan.boot_device and boot_resolver(plan.boot_device) != plan.disk['name']:
        raise InstallError('Stable boot disk identifier changed during preflight.')
    disk = plan.disk['name']
    mounts = []
    try:
        runner.run(['parted', '--script', disk, 'mklabel', 'gpt'])
        if plan.firmware == 'uefi':
            runner.run(['parted', '--script', disk, 'mkpart', 'ESP', 'fat32', '1MiB', '1025MiB', 'set', '1', 'esp', 'on'])
        else:
            runner.run(['parted', '--script', disk, 'mkpart', 'BIOS', '1MiB', '3MiB', 'set', '1', 'bios_grub', 'on'])
        runner.run(['parted', '--script', disk, 'mkpart', 'root', 'ext4', '1025MiB' if plan.firmware == 'uefi' else '3MiB', '100%'])
        runner.run(['partprobe', disk])
        runner.run(['udevadm', 'settle'])
        root = partition_path(disk, 2)
        runner.run(['mkfs.ext4', '-F', root])
        if plan.firmware == 'uefi':
            runner.run(['mkfs.fat', '-F', '32', partition_path(disk, 1)])
        Path(target).mkdir(parents=True, exist_ok=True)
        runner.run(['mount', '-t', 'ext4', root, target])
        mounts.append(target)
        if plan.firmware == 'uefi':
            Path(target, 'boot').mkdir(exist_ok=True)
            runner.run(['mount', '-t', 'vfat', partition_path(disk, 1), str(Path(target, 'boot'))])
            mounts.append(str(Path(target, 'boot')))
        runner.run(['nixos-generate-config', '--root', target])
        config_dir = Path(target, 'etc/nixos')
        config_dir.mkdir(parents=True, exist_ok=True)
        shutil.copytree(source, Path(target, 'etc/sleepy'), symlinks=True)
        (config_dir / 'configuration.nix').write_text(config_text(plan))
        (config_dir / 'flake.nix').write_text(flake_text(plan))
        (config_dir / 'install-plan.json').write_text(json.dumps(plan.manifest(), indent=2) + '\n')
        (config_dir / 'flake.lock').write_text(lock_content)
        # The live system and Nix evaluator share RAM with any source builds.
        runner.run(['nixos-install', '--root', target, '--flake', str(config_dir) + '#' + plan.hostname,
                    '--no-root-passwd', '--max-jobs', '1', '--cores', '1'])
        runner.run(['nixos-enter', '--root', target, '--', '/nix/var/nix/profiles/system/sw/bin/chpasswd'],
                   secret=plan.username + ':' + password + '\n')
        runner.run(['sync'])
    finally:
        # Never unmount unrelated mounts; stop cleanup if a child cannot be unmounted.
        for mount in reversed(mounts):
            try:
                runner.run(['umount', mount])
            except InstallError:
                runner.progress('Cleanup stopped. Unmount the installation filesystem manually before removing media.')
                break


class UI:
    def __init__(self, screen):
        self.s = screen
        curses.curs_set(0)
        curses.start_color()
        self.original_colors = {}
        self.palette = {
            curses.COLOR_BLACK: (0x18, 0x16, 0x20),
            curses.COLOR_WHITE: (0xe8, 0xe2, 0xf0),
            curses.COLOR_CYAN: (0x87, 0xdc, 0xe6),
            curses.COLOR_MAGENTA: (0xb9, 0xa7, 0xff),
            curses.COLOR_GREEN: (0x91, 0xd5, 0xaa),
            curses.COLOR_RED: (0xee, 0x99, 0xa0),
        }
        if curses.can_change_color():
            for slot in self.palette:
                try:
                    self.original_colors[slot] = curses.color_content(slot)
                except curses.error:
                    pass
            self.apply_palette()
        for pair, fg in [(1, curses.COLOR_CYAN), (2, curses.COLOR_MAGENTA), (3, curses.COLOR_WHITE), (4, curses.COLOR_RED), (5, curses.COLOR_GREEN)]:
            curses.init_pair(pair, fg, curses.COLOR_BLACK)
        self.s.bkgd(' ', curses.color_pair(3))
        self.step = 1

    def apply_palette(self):
        for slot in self.original_colors:
            try:
                curses.init_color(slot, *(round(value * 1000 / 255) for value in self.palette[slot]))
            except curses.error:
                pass

    def restore_palette(self):
        for slot, color in self.original_colors.items():
            try:
                curses.init_color(slot, *color)
            except curses.error:
                pass

    def content_width(self):
        return min(100, self.s.getmaxyx()[1])

    def put(self, row, col, text, style=0):
        h, w = self.s.getmaxyx()
        width = min(100, w)
        offset = max(0, (w-width)//2)
        if not style & curses.A_COLOR:
            style |= curses.color_pair(3)
        if 0 <= row < h - 1 and col < width - 1:
            self.s.addnstr(row, offset+col, str(text), max(0, width-col-1), style)

    def frame(self, title, subtitle=''):
        self.s.erase()
        h, w = self.s.getmaxyx()
        self.put(1, 3, 'S L E E P Y', curses.color_pair(2) | curses.A_BOLD)
        self.put(2, 3, 'A quiet start. A system that is yours.', curses.A_DIM)
        self.put(4, 3, '-' * max(1, self.content_width()-7), curses.color_pair(1))
        self.put(6, 3, title, curses.A_BOLD | curses.color_pair(1))
        for row, line in enumerate(textwrap.wrap(subtitle, max(1, self.content_width()-7))[:2]):
            self.put(8+row, 3, line)
        self.put(h-3, 3, 'Up/Down navigate   Space select   Enter continue   Esc cancel', curses.A_DIM)
        self.put(h-2, 3, f'Sleepy Linux  /  installer preview  /  step {self.step}', curses.color_pair(2))
        self.s.refresh()

    def choose(self, title, items, subtitle='', multiple=False, selected=None):
        index = 0
        picked = set(selected or [])
        while True:
            self.frame(title, subtitle)
            height = max(1, self.s.getmaxyx()[0]-15)
            offset = max(0, index-height+1)
            for row, (key, label) in enumerate(items[offset:offset+height]):
                actual = row+offset
                prefix = ('[x] ' if key in picked else '[ ] ') if multiple else '  '
                style = curses.A_REVERSE | curses.color_pair(1) if actual == index else 0
                self.put(10+row, 3, prefix+label, style)
            if multiple:
                self.put(self.s.getmaxyx()[0]-4, 3, f'{len(picked)} selected / Enter keeps your choices', curses.color_pair(5))
            self.s.refresh()
            key = self.s.getch()
            if key == 27:
                raise KeyboardInterrupt
            if key in (curses.KEY_DOWN, ord('j')):
                index = (index+1) % len(items)
            elif key in (curses.KEY_UP, ord('k')):
                index = (index-1) % len(items)
            elif key == ord(' ') and multiple:
                value = items[index][0]
                picked.symmetric_difference_update({value})
            elif key in (10, 13, curses.KEY_ENTER):
                self.step += 1
                return sorted(picked) if multiple else items[index][0]

    def prompt(self, title, subtitle='', secret=False, default=''):
        value = default
        while True:
            self.frame(title, subtitle)
            visible = '*'*len(value) if secret else value
            self.put(11, 3, visible[-max(1, self.content_width()-9):] + '|', curses.color_pair(5))
            self.s.refresh()
            key = self.s.get_wch()
            if key == '\x1b':
                raise KeyboardInterrupt
            if key in ('\n', '\r'):
                self.step += 1
                return value
            if key in (curses.KEY_BACKSPACE, '\x7f', '\b'):
                value = value[:-1]
            elif isinstance(key, str) and key.isprintable() and len(value) < 128:
                value += key

    def validated_prompt(self, title, field, subtitle='', default=''):
        while True:
            value = self.prompt(title, subtitle, secret=field == 'password', default=default)
            error = field_error(field, value)
            if error is None:
                return value
            subtitle = error
            default = '' if field == 'password' else value
            self.step -= 1

    def password(self):
        while True:
            value = self.validated_prompt('Set your password', 'password', 'At least 8 characters. Never written into the installation plan.')
            if value == self.prompt('Confirm your password', secret=True):
                return value
            value = ''
            self.message('Try your password again', ['The passwords did not match. Your other choices are saved.'])
            self.step -= 2

    def message(self, title, lines):
        width = max(1, self.content_width()-7)
        wrapped = [part for line in lines for part in (textwrap.wrap(line, width) or [''])]
        page_size = max(1, self.s.getmaxyx()[0]-14)
        for start in range(0, max(1, len(wrapped)), page_size):
            self.frame(title)
            for row, line in enumerate(wrapped[start:start+page_size]):
                self.put(9+row, 3, line)
            more = start+page_size < len(wrapped)
            self.put(self.s.getmaxyx()[0]-4, 3, 'Press any key for more' if more else 'Press any key to continue', curses.color_pair(5))
            self.s.refresh()
            if self.s.getch() == 27:
                raise KeyboardInterrupt

    def progress(self, message):
        self.frame('Installing your new home', 'Please keep the computer connected to power and the internet.')
        self.put(11, 3, message, curses.color_pair(5))
        self.put(13, 3, 'Building and downloading may take a while. Command output is shown if a step fails.', curses.A_DIM)
        self.s.refresh()


def onboarding(screen, args):
    ui = UI(screen)
    try:
        return _onboarding(ui, args)
    finally:
        ui.restore_palette()


def _onboarding(ui, args):
    screen = ui.s
    ui.message('Welcome home.', ['Install a minimal Sleepy desktop, then make it yours.', '',
        'This preview installer erases one entire disk. Back up your files first.',
        'Storage: ext4, no encryption, no swap. UEFI and legacy BIOS supported.',
        'A working internet connection is required. Configure networking before continuing.',
        'Keep this USB for recovery. Root stays locked; your account uses sudo.'])
    if not args.demo and not args.fixture and not args.dry_run:
        network = ui.choose('Get connected', [('continue', 'Continue / internet is ready'), ('network', 'Configure Wi-Fi or wired networking')], 'The desktop and selected packages will be downloaded during installation.')
        if network == 'network':
            curses.def_prog_mode()
            ui.restore_palette()
            curses.endwin()
            try:
                subprocess.run(['nmtui'], check=True)
            finally:
                curses.reset_prog_mode()
                ui.apply_palette()
                screen.refresh()
    if args.demo:
        disks = [{'name': '/dev/vda', 'type': 'disk', 'size': 128*1024**3, 'model': 'Demo SSD (simulation)',
                  'serial': 'SLEEPY-DEMO-NOT-A-REAL-DISK', 'wwn': None, 'maj:min': '252:0', 'ro': False, 'mountpoints': [None]}]
    else:
        disks = json.loads(Path(args.fixture).read_text())['blockdevices'] if args.fixture else scan_disks()
    safe = [disk for disk in disks if not unsafe_reason(disk)]
    if not safe:
        raise InstallError('No safe installation disk found. Mounted disks, installation media, disks under 32 GiB and disks without serial/WWN are excluded.')
    selection = ui.choose('Choose your installation disk', [(i, f'{d["name"]} / {int(d["size"])/1024**3:.0f} GiB / {str(d.get("model") or "Disk").strip()} / {d.get("serial") or d.get("wwn")}') for i, d in enumerate(safe)], 'All partitions and files on the chosen disk will be erased.')
    plan = Plan(safe[selection], firmware='uefi' if Path('/sys/firmware/efi').exists() else 'bios')
    plan.firmware = ui.choose('Boot mode', [(plan.firmware, f'{plan.firmware.upper()} / detected firmware'), ('bios' if plan.firmware == 'uefi' else 'uefi', 'BIOS / override' if plan.firmware == 'uefi' else 'UEFI / override')], 'Use detected firmware unless you deliberately booted the installer in another mode.')
    plan.boot_device = '/dev/disk/by-id/virtio-SLEEPY-DEMO' if (args.demo or args.fixture) else disk_by_id(plan.disk)
    plan.validate()
    plan.hostname = ui.validated_prompt('Name your computer', 'hostname', 'Lowercase letters, digits and hyphens.', default='sleepy')
    plan.username = ui.validated_prompt('Create your account', 'username', 'This account will have sudo access.', default='sleepy')
    plan.timezone = ui.choose('Your time zone', [(z,z) for z in TIMEZONES])
    plan.keyboard = ui.choose('Your keyboard', [(k, 'US + RU (Alt+Shift)' if k == 'ru' else k.upper()) for k in KEYBOARDS], 'Input here still uses the live console layout; the selected layout applies after reboot.')
    gpu, explanation = detected_gpu() if not (args.fixture or args.demo) else ('auto', 'Demo graphics; no hardware probing.')
    plan.gpu = ui.choose('Graphics drivers', [(g,g.upper() + (' / detected' if g == gpu else '')) for g in [gpu]+[g for g in GPU_CHOICES if g != gpu]], explanation)
    if plan.gpu == 'nvidia':
        plan.nvidia_open = ui.choose('NVIDIA kernel module', [(True, 'Open kernel module / modern NVIDIA GPUs'), (False, 'Proprietary kernel module / older supported NVIDIA GPUs')], 'Check your GPU generation. Recent GPUs require the open module; older GPUs may need proprietary.')
        pair = detect_prime() if not (args.fixture or args.demo) else None
        if pair:
            plan.nvidia_mode = ui.choose('NVIDIA graphics mode', [('offload', 'PRIME offload / integrated graphics plus NVIDIA on demand'), ('dedicated', 'Dedicated / NVIDIA drives the desktop')], 'Two GPUs detected. Offload reduces power use; launch games with nvidia-offload.')
            if plan.nvidia_mode == 'offload':
                plan.prime = pair
        else:
            ui.message('NVIDIA dedicated mode', ['No unambiguous NVIDIA + integrated GPU pair was detected.', 'The installer will use dedicated NVIDIA graphics.', 'Complex multi-GPU setups require manual configuration after installation.'])
    plan.packages = []
    for category, choices in PACKAGES.items():
        plan.packages += ui.choose(category, list(choices.items()), 'Choose extras. The Sleepy desktop and terminal are included.', multiple=True, selected=['firefox'] if category == 'Apps' else [])
    plan.validate()
    password = ui.password()
    ui.message('Review your installation', [f'DESTROY ALL DATA ON {plan.disk["name"]}',
        f'Identity: {plan.disk.get("serial") or plan.disk.get("wwn")}',
        'Boot device: ' + (plan.boot_device or 'UEFI partition UUID'),
        f'{plan.hostname} / {plan.username} / {plan.timezone} / {plan.keyboard}',
        f'Boot: {plan.firmware.upper()} / Graphics: {plan.gpu}' + (f' / {plan.nvidia_mode} / ' + ('open' if plan.nvidia_open else 'proprietary') if plan.gpu == 'nvidia' else ''),
        'Extras: ' + (', '.join(plan.packages) or 'none'),
        'GPT partition table / ext4 root / unencrypted / no swap',
        'Root locked / use your password with sudo / keep USB for recovery'])
    if args.dry_run or args.fixture or args.demo:
        password = ''
        ui.message('Preview complete', ['No disk or account changes were made.', json.dumps(plan.manifest())])
        return
    confirmation = ui.prompt('Last chance: erase this disk?', 'Type exactly: ERASE ' + plan.disk['name'])
    execute(plan, password, confirmation, os.environ.get('SLEEPY_SOURCE', '/etc/sleepy-source'), Runner(ui.progress))
    password = ''
    ui.message('You are home.', ['Installation finished. Remove the USB after shutdown, then start your computer.',
        f'Log in as {plan.username}. Use sudo with your password for administration.',
        'Recovery: boot this USB, mount the root disk, then use nixos-enter --root /mnt.',
        'You can reset your user password there with passwd. Root login remains locked.'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--dry-run', action='store_true', help='Preview onboarding without writing anything')
    parser.add_argument('--demo', action='store_true', help='Simulated onboarding; never probes or writes disks')
    parser.add_argument('--fixture', help='Use lsblk JSON fixture; always implies dry-run')
    parser.add_argument('--list-disks', action='store_true', help='Print read-only disk inventory and eligibility')
    args = parser.parse_args()
    if args.list_disks:
        print(json.dumps([dict(disk, excluded=unsafe_reason(disk)) for disk in scan_disks()], indent=2))
        return 0
    if not args.dry_run and not args.fixture and not args.demo and os.geteuid() != 0:
        parser.error('Run sudo sleepy-install, or use --dry-run to preview.')
    try:
        curses.wrapper(onboarding, args)
    except KeyboardInterrupt:
        print('Installation cancelled.')
        return 130
    except (InstallError, OSError, subprocess.SubprocessError, ValueError, curses.error) as error:
        print(f'Installation stopped: {error}', file=sys.stderr)
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
