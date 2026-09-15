#!/usr/bin/env python3
"""Constrained offline boot repair for the installer's original two-partition layout."""
import argparse
from collections import deque
from contextlib import contextmanager
import fcntl
import hashlib
import json
from itertools import islice
import os
from pathlib import Path, PurePosixPath
import re
import signal
import stat
import sys

import backend

ROOT = Path('/mnt/sleepy-recovery')
ESP_TYPE = 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'
LINUX_TYPE = '0fc63daf-8483-4772-8e79-3d69d8477de4'
SYSTEM = re.compile(r'/nix/store/[0-9a-z]{32}-nixos-system-[A-Za-z0-9._+-]+')


def validate_request(data, restore):
    fields = {'disk', 'identity'} | ({'installation', 'confirm_restore'} if restore else set())
    if not isinstance(data, dict) or set(data) != fields or any(not isinstance(v, str) for v in data.values()):
        raise backend.InstallError('Invalid recovery request fields')
    if not re.fullmatch(r'/dev/[A-Za-z0-9_-]+', data['disk']) or not re.fullmatch(r'[0-9a-f]{64}', data['identity']):
        raise backend.InstallError('Invalid recovery disk identity')
    if restore and (not re.fullmatch(r'[0-9a-f]{64}', data['installation']) or data['confirm_restore'] != data['disk']):
        raise backend.InstallError('Boot repair confirmation does not match the inspected disk')
    return data


def rooted(root, name):
    """Resolve installed absolute links inside root, never against the image OS."""
    todo = deque(PurePosixPath(name).parts)
    resolved = []
    links = 0
    while todo:
        part = todo.popleft()
        if part in ('/', '//', '.', ''): continue
        if part == '..':
            if not resolved: raise backend.InstallError('Installed path escapes its filesystem root')
            resolved.pop(); continue
        path = root.joinpath(*resolved, part)
        if stat.S_ISLNK(path.lstat().st_mode):
            links += 1
            if links > 40: raise backend.InstallError('Installed path contains a symlink loop')
            target = PurePosixPath(os.readlink(path))
            if target.is_absolute(): resolved = []
            todo.extendleft(reversed(target.parts))
        else:
            resolved.append(part)
    return root.joinpath(*resolved)


def read_small(path, limit=65536):
    info = path.stat(follow_symlinks=False)
    if not stat.S_ISREG(info.st_mode) or info.st_size > limit:
        raise backend.InstallError('Installed recovery metadata is not a bounded regular file')
    with path.open('rb') as stream:
        content = stream.read(limit + 1)
    if len(content) > limit: raise backend.InstallError('Installed recovery metadata is too large')
    return content


def inspect_installation(root):
    release = read_small(rooted(root, '/etc/os-release'))
    if not re.search(rb'^ID=(?:sleepy|"sleepy")$', release, re.MULTILINE):
        raise backend.InstallError('The selected filesystem is not an installed Sleepy system')
    for name in ('boot', 'dev', 'sys', 'proc', 'run'):
        directory = root / name
        if not stat.S_ISDIR(directory.lstat().st_mode) or directory.is_symlink():
            raise backend.InstallError(f'Installed /{name} must be a real directory')
    profiles = rooted(root, '/nix/var/nix/profiles')
    system = '/' + rooted(root, '/nix/var/nix/profiles/system').relative_to(root).as_posix()
    if not SYSTEM.fullmatch(system): raise backend.InstallError('Installed system profile is not a retained NixOS store generation')
    with os.scandir(profiles) as directory:
        entries = [profiles / entry.name for entry in islice(directory, 513)]
    if len(entries) > 512: raise backend.InstallError('Too many profile entries for guided recovery')
    generations = []
    for entry in entries:
        match = re.fullmatch(r'system-([1-9][0-9]{0,8})-link', entry.name)
        if match is None: continue
        if not entry.is_symlink(): raise backend.InstallError('Retained generation is not a profile link')
        target = '/' + rooted(root, '/nix/var/nix/profiles/' + entry.name).relative_to(root).as_posix()
        if not SYSTEM.fullmatch(target): raise backend.InstallError('Retained generation points outside the NixOS store')
        generations.append(dict(generation=int(match[1]), system=target, modified=entry.lstat().st_mtime_ns))
    generations.sort(key=lambda item: item['generation'])
    profile = profiles / 'system'
    if not profile.is_symlink(): raise backend.InstallError('Current system profile must be a generation link')
    selected = re.fullmatch(r'(?:/nix/var/nix/profiles/)?system-([1-9][0-9]{0,8})-link', os.readlink(profile))
    if selected is None: raise backend.InstallError('Current system profile has an unsupported link target')
    current = int(selected[1])
    if not any(item['generation'] == current and item['system'] == system for item in generations):
        raise backend.InstallError('Current profile has no retained generation')
    program = rooted(root, system + '/bin/switch-to-configuration')
    repair = read_small(program, 1024 * 1024)
    if not program.stat().st_mode & 0o111: raise backend.InstallError('Installed boot repair program is not executable')
    metadata = dict(current=current, generations=generations, system=system)
    digest = hashlib.sha256(release + repair + json.dumps(metadata, sort_keys=True).encode()).hexdigest()
    return dict(metadata, installation=digest)


def partition_layout(data):
    backend.verify_target(data)
    result = json.loads(backend.run(['lsblk', '--json', '--tree', '--paths', '--properties-by', 'blkid', '--output',
        'PATH,TYPE,FSTYPE,PARTTYPE,PTTYPE,UUID', data['disk']]))
    nodes = result.get('blockdevices', [])
    if len(nodes) != 1 or nodes[0].get('path') != data['disk'] or nodes[0].get('pttype') != 'gpt':
        raise backend.InstallError('Guided recovery requires the original Sleepy GPT layout')
    parts = nodes[0].get('children', [])
    suffix = 'p' if data['disk'][-1].isdigit() else ''
    expected = [(data['disk'] + suffix + '1', 'vfat', ESP_TYPE), (data['disk'] + suffix + '2', 'btrfs', LINUX_TYPE)]
    if len(parts) != 2: raise backend.InstallError('Guided recovery supports exactly an ESP and Btrfs root')
    parts.sort(key=lambda item: item.get('path', ''))
    for part, (path, filesystem, kind) in zip(parts, expected):
        if (part.get('path'), part.get('fstype'), str(part.get('parttype', '')).lower()) != (path, filesystem, kind) or part.get('type') != 'part' or part.get('children') or not part.get('uuid'):
            raise backend.InstallError('Selected partitions do not match the supported Sleepy layout')
    backend.verify_target(data)
    return dict(esp=expected[0][0], root=expected[1][0])


def private_namespace():
    os.unshare(os.CLONE_NEWNS)
    backend.run(['mount', '--make-rprivate', '/'])


@contextmanager
def recovery_lock():
    if os.geteuid() != 0 or not Path('/etc/sleepy-installer-image').is_file():
        raise backend.InstallError('Boot the dedicated Sleepy installer image for guided recovery')
    if not Path('/sys/firmware/efi').is_dir(): raise backend.InstallError('Boot the recovery image in UEFI mode')
    descriptor = os.open('/run/sleepy-installer.lock', os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != 0:
            raise backend.InstallError('Recovery lock is not a root-owned regular file')
        try: fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise backend.InstallError('Another installation or recovery operation is running') from None
        if ROOT.is_symlink() or ROOT.exists() and (os.path.ismount(ROOT) or any(ROOT.iterdir())):
            raise backend.InstallError('Recovery mount directory is already in use')
        ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = ROOT.lstat()
        if not stat.S_ISDIR(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o022:
            raise backend.InstallError('Recovery mount directory must be root-owned and not writable by other users')
        private_namespace()
        yield
    finally:
        os.close(descriptor)


@contextmanager
def mounted_root(layout, writable=False):
    if os.path.ismount(ROOT):
        raise backend.InstallError('Recovery mount directory already has an unowned mount')
    # Linux 6.18 accepts rescue=nologreplay, not the old standalone spelling.
    # Preserve replay protection: a plain read-only Btrfs mount may write its log.
    options = 'rw,nosuid,nodev' if writable else 'ro,rescue=nologreplay,nosuid,nodev,noexec'
    try:
        backend.run(['mount', '-t', 'btrfs', '-o', options, layout['root'], str(ROOT)])
        yield
    finally:
        # The command may have completed mounting just before SIGTERM arrived.
        # Our private namespace and initially empty mountpoint identify ownership.
        if os.path.ismount(ROOT):
            backend.run(['umount', '--recursive', str(ROOT)])


def prepare_chroot():
    for name in ('dev', 'sys', 'proc'):
        backend.run(['mount', '--rbind', '/' + name, str(ROOT / name)])
    # switch-to-configuration boot needs its lock and syslog endpoint, but must
    # not write recovery runtime files into the installed filesystem.
    backend.run(['mount', '-t', 'tmpfs', '-o', 'mode=0755,nosuid,nodev', 'tmpfs', str(ROOT / 'run')])
    journal = ROOT / 'run/systemd/journal'
    journal.mkdir(parents=True)
    (journal / 'dev-log').touch()
    backend.run(['mount', '--bind', '/run/systemd/journal/dev-log', str(journal / 'dev-log')])


def recover(data, restore=False):
    with recovery_lock():
        layout = partition_layout(data)
        with mounted_root(layout):
            metadata = inspect_installation(ROOT)
        if not restore: return dict(metadata, disk=data['disk'], identity=data['identity'])
        if metadata['installation'] != data['installation']:
            raise backend.InstallError('Installed generations changed; inspect and confirm again')
        # Final busy/hotplug/fingerprint check immediately before writable mounts.
        if partition_layout(data) != layout:
            raise backend.InstallError('Installed partition layout changed')
        backend.emit('repair', 'Restoring boot entries from the inspected installed system', 20)
        with mounted_root(layout, writable=True):
            if inspect_installation(ROOT)['installation'] != data['installation']:
                raise backend.InstallError('Installed system changed before boot repair')
            backend.run(['mount', '-t', 'vfat', '-o', 'rw,nosuid,nodev,noexec,umask=0077', layout['esp'], str(ROOT / 'boot')])
            # Fixed operation only: the user explicitly trusts repair code from
            # this installed OS. No UI-provided shell text or store path is run.
            prepare_chroot()
            backend.run(['timeout', '--signal=TERM', '--kill-after=10s', '300s', 'env',
                'NIXOS_INSTALL_BOOTLOADER=1', 'chroot', str(ROOT),
                '/nix/var/nix/profiles/system/bin/switch-to-configuration', 'boot'])
            backend.run(['sync'])
        backend.emit('complete', 'Boot entries restored. Shut down, remove the image, and boot the installed disk.', 100)


def interrupted(signum, frame):
    raise backend.InstallError('Boot repair interrupted; inspect diagnostics before retrying. User data was not restored or rolled back.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--inspect', action='store_true')
    group.add_argument('--restore', action='store_true')
    args = parser.parse_args()
    try:
        raw = sys.stdin.read(4097)
        if len(raw) > 4096: raise backend.InstallError('Recovery request too large')
        data = validate_request(json.loads(raw), args.restore)
        if os.geteuid() != 0: raise backend.InstallError('Recovery requires root')
        backend.LOG = backend.open_log()
        signal.signal(signal.SIGTERM, interrupted)
        signal.signal(signal.SIGINT, interrupted)
        result = recover(data, args.restore)
        if args.inspect: print(json.dumps(result))
        return 0
    except (backend.InstallError, ValueError, OSError, KeyboardInterrupt) as error:
        message = str(error) if isinstance(error, backend.InstallError) else 'Recovery stopped; inspect /var/log/sleepy-installer.log'
        backend.emit('error', message, 0)
        return 1
    finally:
        if backend.LOG is not None:
            backend.LOG.close(); backend.LOG = None


if __name__ == '__main__': sys.exit(main())
