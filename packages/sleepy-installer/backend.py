#!/usr/bin/env python3
"""Sleepy's privileged, fixed-operation installer. No command text comes from the UI."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import signal
import tempfile
import urllib.request
import subprocess
import sys

ROOT = Path('/mnt/sleepy')
OPTIONS = {'nvidia', 'gaming', 'development', 'flatpak', 'bluetooth'}
LOCALES = {'en_US.UTF-8', 'ru_RU.UTF-8', 'de_DE.UTF-8', 'cs_CZ.UTF-8'}
KEYBOARDS = {'us', 'ru', 'de', 'cz'}
LOG_PATH = Path('/var/log/sleepy-installer.log')
LOG = None
RESERVED_USERS = {'root', 'nobody', 'nixbld', 'daemon', 'bin', 'sys', 'sync', 'games',
                  'man', 'lp', 'mail', 'news', 'uucp', 'proxy', 'www-data', 'backup',
                  'list', 'irc', 'gnats', 'sshd', 'polkituser', 'messagebus', 'avahi',
                  'chrony', 'ntp', 'dnsmasq', 'rtkit', 'nscd', 'nm-openvpn', 'mandb', 'greetd', 'greeter', 'nixos',
                  'systemd-network', 'sleepy-installer'}


class InstallError(Exception):
    pass


def emit(stage, message, progress):
    print(json.dumps(dict(stage=stage, message=message, progress=progress)), flush=True)


def open_log():
    fd = os.open(LOG_PATH, os.O_CREAT | os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0:
        os.close(fd)
        raise InstallError('Diagnostics path is not a root-owned regular file')
    os.fchmod(fd, 0o600)
    return os.fdopen(fd, 'w', encoding='utf-8')


def log_output(value):
    if LOG is not None:
        if LOG.tell() > 16 * 1024 * 1024:
            LOG.seek(0); LOG.truncate()
            LOG.write('[Earlier diagnostics truncated at 16 MiB]\n')
        LOG.write(value); LOG.flush()


def run(argv, secret=None):
    # Credential subprocess output is discarded, including on errors.
    if secret is not None:
        result = subprocess.run(argv, input=secret, text=True, stdout=subprocess.DEVNULL,
                                stderr=subprocess.DEVNULL, check=False)
        code, output = result.returncode, ''
    else:
        log_output('> ' + ' '.join(argv) + '\n')
        captured = []
        captured_size = 0
        with subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, start_new_session=True) as process:
            try:
                while True:
                    chunk = process.stdout.read1(4096)
                    if not chunk: break
                    value = chunk.decode('utf-8', errors='replace')
                    log_output(value)
                    if captured_size < 1024 * 1024:
                        captured.append(value)
                        captured_size += len(chunk)
                code = process.wait()
            except BaseException:
                try: os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError: pass
                try: process.wait(timeout=10)
                except subprocess.TimeoutExpired: pass
                # Also stop descendant build/install processes before unmounting.
                try: os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError: pass
                process.wait()
                raise
        output = ''.join(captured)
    if code:
        raise InstallError(f'{Path(argv[0]).name} failed (exit {code}); see /var/log/sleepy-installer.log')
    return output


def check_network():
    try:
        with urllib.request.urlopen('https://cache.nixos.org/nix-cache-info', timeout=20) as response:
            if b'StoreDir: /nix/store' not in response.read(4096):
                raise InstallError('Unexpected binary cache response; check your network')
    except (OSError, ValueError) as error:
        raise InstallError('Cannot reach the NixOS binary cache. Connect the network before installation.') from error


def interrupted(signum, frame):
    raise InstallError('Installation interrupted. Existing data cannot be restored; inspect diagnostics before retrying.')


def descendants(node):
    yield node
    for child in node.get('children', []):
        yield from descendants(child)


def disk_sequence(path):
    try:
        return (Path('/sys/class/block') / Path(path).name / 'diskseq').read_text().strip()
    except OSError:
        return None


def describe_disk(node, swaps):
    path = node.get('path', '')
    reason = ''
    if re.fullmatch(r'(?:zram|ram|loop)[0-9]+', Path(path).name): reason = 'Memory and loop devices are not persistent installation disks'
    elif node.get('type') != 'disk': reason = 'Not a whole disk'
    elif node.get('ro'): reason = 'Read-only device'
    elif node.get('rm'): reason = 'Removable media is protected'
    elif int(node.get('size') or 0) < 16 * 1024**3: reason = 'At least 16 GiB required'
    for child in descendants(node):
        if any(child.get('mountpoints') or []) or child.get('path') in swaps:
            reason = 'Disk or descendant is mounted or used as swap'
        holders = Path('/sys/class/block') / Path(child.get('path', 'missing')).name / 'holders'
        if holders.is_dir() and any(holders.iterdir()): reason = 'Device is held by another block device'
    fingerprint = [{k: child.get(k) for k in ('path', 'maj:min', 'size', 'serial', 'wwn', 'type', 'uuid', 'partuuid', 'ptuuid', 'fstype')}
                   for child in descendants(node)]
    sequence = disk_sequence(path)
    identity = hashlib.sha256(json.dumps({'devices': fingerprint, 'diskseq': sequence}, sort_keys=True).encode()).hexdigest()
    return dict(path=path, identity=identity, diskseq=sequence, model=str(node.get('model') or '').strip(),
                size=int(node.get('size') or 0), serial=str(node.get('serial') or '').strip(),
                eligible=not reason, reason=reason)


def list_disks():
    payload = json.loads(run(['lsblk', '--json', '--bytes', '--paths', '--properties-by', 'blkid', '--output',
                            'PATH,TYPE,SIZE,RO,RM,MAJ:MIN,MODEL,SERIAL,WWN,MOUNTPOINTS,UUID,PARTUUID,PTUUID,FSTYPE']))
    swaps = set()
    for line in Path('/proc/swaps').read_text().splitlines()[1:]:
        swaps.add(os.path.realpath(line.split()[0]))
    disks = [describe_disk(node, swaps) for node in payload['blockdevices'] if node.get('type') == 'disk']
    for disk in disks:
        if not Path('/etc/sleepy-installer-image').is_file():
            disk.update(eligible=False, reason='Boot the dedicated Sleepy installer image to select installation targets')
        try:
            if not stat.S_ISBLK(os.stat(disk['path'], follow_symlinks=False).st_mode):
                raise OSError('not a block device')
        except OSError:
            disk.update(eligible=False, reason='Block device is unavailable in this environment')
    return disks


def validate_request(data):
    required = {'disk', 'identity', 'confirm_erase', 'username', 'password', 'hostname',
                'locale', 'keyboard', 'timezone', 'options'}
    if not isinstance(data, dict) or set(data) != required:
        raise InstallError('Invalid installation request fields')
    if any(not isinstance(data[k], str) for k in required - {'options'}):
        raise InstallError('Installation settings must be strings')
    if not re.fullmatch(r'/dev/[A-Za-z0-9_-]+', data['disk']): raise InstallError('Invalid disk path')
    if not re.fullmatch(r'[0-9a-f]{64}', data['identity']): raise InstallError('Invalid disk identity')
    if data['confirm_erase'] != data['disk']: raise InstallError('Erase confirmation does not match selected disk')
    if not re.fullmatch(r'[a-z][a-z0-9_-]{0,30}', data['username']) or data['username'] in RESERVED_USERS or data['username'].startswith(('nixbld', 'systemd-')):
        raise InstallError('Invalid user name')
    if not re.fullmatch(r'[a-z0-9][a-z0-9-]{0,61}[a-z0-9]|[a-z0-9]', data['hostname']):
        raise InstallError('Invalid host name')
    if len(data['password']) < 8 or len(data['password'].encode()) > 1024 or any(c in data['password'] for c in '\n\r\x00'):
        raise InstallError('Password must contain 8 or more characters and no line breaks')
    if data['locale'] not in LOCALES or data['keyboard'] not in KEYBOARDS:
        raise InstallError('Unsupported locale or keyboard')
    zone = data['timezone']
    zone_root = Path(os.environ.get('SLEEPY_ZONEINFO', '/usr/share/zoneinfo')).resolve()
    zone_path = (zone_root / zone).resolve()
    if not re.fullmatch(r'[A-Za-z0-9_+/-]+', zone) or '..' in zone or not zone_path.is_relative_to(zone_root) or not zone_path.is_file():
        raise InstallError('Invalid timezone')
    if not isinstance(data['options'], dict) or set(data['options']) - OPTIONS or any(type(v) is not bool for v in data['options'].values()):
        raise InstallError('Invalid optional feature selection')
    return data


def verify_target(data):
    selected = next((disk for disk in list_disks() if disk['path'] == data['disk']), None)
    if selected is None or selected['identity'] != data['identity']:
        raise InstallError('Disk identity changed; rescan and select it again')
    if not selected['eligible']: raise InstallError(selected['reason'])
    return selected


def nix_string(value):
    return json.dumps(value).replace('${', r'\${')


def render_configuration(data):
    features = []
    for name in sorted(OPTIONS):
        if data['options'].get(name, False):
            path = 'sleepy.hardware.nvidia' if name == 'nvidia' else f'sleepy.features.{name}'
            features.append(f'  {path}.enable = true;')
    return '''{ ... }: {
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = false;
  networking.networkmanager.enable = true;
  users.mutableUsers = true;
  users.users.root.hashedPassword = "!";
  system.stateVersion = "26.05";
''' + f'''  i18n.defaultLocale = {nix_string(data['locale'])};
  console.keyMap = {nix_string(data['keyboard'])};
  services.xserver.xkb.layout = {nix_string(data['keyboard'])};
  time.timeZone = {nix_string(data['timezone'])};
''' + '\n'.join(features) + '\n}\n'


def write_configuration(data, source, target=None):
    target = ROOT / 'etc/nixos' if target is None else target
    target.mkdir(parents=True, exist_ok=True)
    shutil.copytree(source, target / 'sleepy-source', symlinks=True)
    (target / 'configuration.nix').write_text(render_configuration(data))
    (target / 'flake.nix').write_text('''{
  inputs.sleepy.url = "path:./sleepy-source";
  inputs.nixpkgs.follows = "sleepy/nixpkgs";
  inputs.home-manager.follows = "sleepy/home-manager";
  outputs = { sleepy, ... }: {
    nixosConfigurations.installed = sleepy.lib.mkSleepyHost {
      system = "x86_64-linux";
''' + f'''      hostName = {nix_string(data['hostname'])};
      primaryUser = {nix_string(data['username'])};
''' + '''      hardwareModule = ./hardware-configuration.nix;
      extraModules = [ ./configuration.nix ];
    };
  };
}
''')


def preflight_configuration(data, source):
    # Evaluate the actual selected modules before touching the target. This catches
    # NixOS assertions (including system-account collisions) and missing pinned inputs.
    with tempfile.TemporaryDirectory(prefix='sleepy-preflight-', dir='/run') as directory:
        target = Path(directory)
        write_configuration(data, source, target=target)
        (target / 'hardware-configuration.nix').write_text('''{ ... }: {
  fileSystems."/" = { device = "/dev/disk/by-label/sleepy-root"; fsType = "btrfs"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/SLEEPY_EFI"; fsType = "vfat"; };
  nixpkgs.hostPlatform = "x86_64-linux";
}
''')
        run(['nix', 'eval', '--raw', str(target) + '#nixosConfigurations.installed.config.system.build.toplevel.drvPath'])


def install(data):
    validate_request(data)
    if os.geteuid() != 0: raise InstallError('Installation requires root')
    if not Path('/etc/sleepy-installer-image').is_file():
        raise InstallError('Boot the dedicated Sleepy installer image to install')
    if not Path('/sys/firmware/efi').is_dir(): raise InstallError('Boot the installer in UEFI mode')
    source = Path(os.environ.get('SLEEPY_SOURCE', '/nonexistent'))
    if not (source / 'flake.nix').is_file() or not (source / 'flake.lock').is_file():
        raise InstallError('Installer source or pinned lock file is missing')
    if ROOT.exists() and (os.path.ismount(ROOT) or any(ROOT.iterdir())):
        raise InstallError('Installation mount directory is already in use; recover/unmount it first')
    ROOT.mkdir(parents=True, exist_ok=True)
    lock = os.open('/run/sleepy-installer.lock', os.O_CREAT | os.O_RDWR | os.O_CLOEXEC, 0o600)
    mounted = False
    device = None
    try:
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise InstallError('Another installation is running') from None
        emit('network', 'Checking network access before erasing the disk', 1)
        check_network()
        emit('preflight', 'Checking selected system configuration before erasing the disk', 2)
        preflight_configuration(data, source)
        original_disk = verify_target(data)
        original_rdev = os.stat(data['disk']).st_rdev
        try:
            device = os.open(data['disk'], os.O_RDWR | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW)
        except OSError: raise InstallError('Disk is busy or unavailable') from None
        if not stat.S_ISBLK(os.fstat(device).st_mode): raise InstallError('Target is not a block device')
        # Last check while exclusive block-device claim is held, before first write.
        verify_target(data)
        if os.stat(data['disk']).st_rdev != os.fstat(device).st_rdev:
            raise InstallError('Target device changed while opening it')
        emit('partition', 'Erasing selected disk and creating GPT partitions', 5)
        # wipefs otherwise takes a second O_EXCL claim and fails against our own.
        # --force is safe here only because our verified exclusive claim is held.
        run(['wipefs', '--all', '--force', data['disk']])
        run(['parted', '--script', data['disk'], 'mklabel', 'gpt', 'mkpart', 'ESP', 'fat32', '1MiB', '513MiB',
             'set', '1', 'esp', 'on', 'mkpart', 'Sleepy', 'btrfs', '513MiB', '100%'])
        # Partition formatters need their own exclusive block-device claims.
        # Keep our process-wide installer lock, release the whole-disk claim.
        os.close(device); device = None
        run(['udevadm', 'settle'])
        suffix = 'p' if data['disk'][-1].isdigit() else ''
        esp, root = (data['disk'] + suffix + str(n) for n in (1, 2))
        current_disk = next((d for d in list_disks() if d['path'] == data['disk']), None)
        if current_disk is None or not current_disk['eligible'] or any(current_disk[k] != original_disk[k] for k in ('model', 'serial', 'size', 'diskseq')) or os.stat(data['disk']).st_rdev != original_rdev:
            raise InstallError('Disk changed or became busy after partitioning; stopping before format')
        emit('format', 'Creating FAT32 EFI and Btrfs root filesystems', 12)
        run(['mkfs.fat', '-F', '32', '-n', 'SLEEPY_EFI', esp])
        run(['mkfs.btrfs', '-f', '-L', 'sleepy-root', root])
        run(['mount', '-o', 'compress=zstd', root, str(ROOT)]); mounted = True
        (ROOT / 'boot').mkdir()
        run(['mount', '-o', 'umask=0077', esp, str(ROOT / 'boot')])
        emit('configure', 'Generating hardware configuration and selected features', 20)
        run(['nixos-generate-config', '--root', str(ROOT)])
        write_configuration(data, source)
        emit('install', 'Downloading and installing Sleepy; this can take a while', 30)
        run(['nixos-install', '--root', str(ROOT), '--no-root-passwd', '--flake', str(ROOT / 'etc/nixos') + '#installed'])
        emit('account', 'Setting your account password', 90)
        run(['chpasswd', '--crypt-method', 'SHA512', '--root', str(ROOT)], secret=data['username'] + ':' + data['password'] + '\n')
        emit('sync', 'Saving files and unmounting the installed disk', 95)
        run(['sync'])
        run(['umount', '--recursive', str(ROOT)]); mounted = False
        emit('complete', 'Installation complete. Shut down, remove installer media, then boot the disk.', 100)
    finally:
        if mounted:
            try: run(['umount', '--recursive', str(ROOT)])
            except InstallError: print('Cleanup could not unmount /mnt/sleepy; unmount it before retrying.', file=sys.stderr)
        if device is not None: os.close(device)
        os.close(lock)


def main():
    global LOG
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--list', action='store_true')
    group.add_argument('--install', action='store_true')
    args = parser.parse_args()
    try:
        if args.list: print(json.dumps(list_disks()))
        else:
            raw = sys.stdin.read(16385)
            if len(raw) > 16384: raise InstallError('Installation request too large')
            data = validate_request(json.loads(raw))
            if os.geteuid() != 0: raise InstallError('Installation requires root')
            LOG = open_log()
            signal.signal(signal.SIGTERM, interrupted)
            signal.signal(signal.SIGINT, interrupted)
            install(data)
    except (InstallError, ValueError, OSError, KeyboardInterrupt) as error:
        message = str(error) if isinstance(error, InstallError) else 'Installation stopped; inspect root-only diagnostics and disk state before retrying'
        emit('error', message, 0)
        return 1
    finally:
        if LOG is not None:
            LOG.close(); LOG = None
    return 0


if __name__ == '__main__':
    sys.exit(main())
