"""Trusted, staged NixOS updates; no disk selection or generation deletion."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys
import tempfile

from snug import SnugError, mutation_lock, run

CONFIG = Path('/etc/snug/system.json')
STATE = Path('/var/lib/snug')
PROFILE = Path('/nix/var/nix/profiles/system')
STORE = Path('/nix/store')
# Root operations never search a caller-controlled PATH for privileged commands.
NIX = ['/run/current-system/sw/bin/nix', '--extra-experimental-features',
       'nix-command flakes', '--option', 'accept-flake-config', 'false']
NIX_ENV = '/run/current-system/sw/bin/nix-env'


def trusted(path, directory=False):
    """Reject writable ancestors, symlinks and special files before reading."""
    path = Path(path)
    if not path.is_absolute():
        raise SnugError(f'System update path must be absolute: {path}')
    for entry in [*reversed(path.parents), path]:
        info = os.lstat(entry)
        if info.st_uid != 0 or info.st_mode & 0o022:
            raise SnugError(f'System update path must be root-owned and not group/world writable: {entry}')
        want_directory = entry != path or directory
        if not (stat.S_ISDIR(info.st_mode) if want_directory else stat.S_ISREG(info.st_mode)):
            raise SnugError(f'System update path must be a regular {"directory" if want_directory else "file"}, not a symlink: {entry}')
    return path


def configuration():
    trusted(CONFIG)
    with CONFIG.open() as stream:
        config = json.load(stream)
    if not isinstance(config, dict) or set(config) != {'flake', 'host', 'input', 'source'}:
        raise SnugError('System configuration requires exactly flake, host, input and source fields.')
    if not all(isinstance(value, str) and value for value in config.values()):
        raise SnugError('System configuration fields must be nonempty strings.')
    for field in ('host', 'input'):
        if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_-]*', config[field]):
            raise SnugError(f'Invalid system {field} name.')
    if not config['source'].startswith('github:') or any(c.isspace() for c in config['source']):
        raise SnugError('System source must be an explicit github: flake reference.')
    source = trusted(Path(config['flake']), directory=True)
    if source == STATE or source in STATE.parents:
        raise SnugError('Host flake directory must not contain the Snug staging directory.')
    # The tree must be self-contained. Reject links instead of silently copying
    # mutable code outside the root-owned host configuration.
    for current, directories, files in os.walk(source, followlinks=False):
        directories[:] = [name for name in directories if name != '.git']
        for name in directories:
            trusted(Path(current) / name, directory=True)
        for name in files:
            if name != '.git':
                trusted(Path(current) / name)
    trusted(source / 'flake.nix')
    return config, source


def store_system(path):
    resolved = Path(path).resolve(strict=True)
    if resolved.parent != STORE:
        raise SnugError('System generation must resolve to a top-level Nix store path.')
    if not (resolved / 'bin/switch-to-configuration').is_file():
        raise SnugError('Built output is not a NixOS system generation.')
    return resolved


def current_generation():
    target = os.readlink(PROFILE)
    match = re.fullmatch(r'system-([0-9]+)-link', Path(target).name)
    if not match:
        raise SnugError('Cannot identify the current NixOS profile generation.')
    return int(match[1]), store_system(PROFILE)


def atomic_write(path, content):
    fd, temporary = tempfile.mkstemp(prefix='.snug-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        os.chmod(temporary, 0o644)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def activate(target, previous_number, previous_system, generation=None):
    run([str(target / 'bin/switch-to-configuration'), 'dry-activate'])
    try:
        if generation is None:
            run([NIX_ENV, '--profile', str(PROFILE), '--set', str(target)])
        else:
            run([NIX_ENV, '--profile', str(PROFILE), '--switch-generation', str(generation)])
        run([str(target / 'bin/switch-to-configuration'), 'switch'])
    except (subprocess.CalledProcessError, OSError, KeyboardInterrupt):
        restore(previous_number, previous_system)
        raise


def restore(number, system):
    try:
        run([NIX_ENV, '--profile', str(PROFILE), '--switch-generation', str(number)])
        run([str(system / 'bin/switch-to-configuration'), 'switch'])
    except (subprocess.CalledProcessError, OSError, KeyboardInterrupt) as error:
        print(f'snug: restoring generation {number} failed; use the boot menu for recovery ({type(error).__name__}).', file=sys.stderr)


def update():
    config, source = configuration()
    previous_number, previous_system = current_generation()
    stage = Path(tempfile.mkdtemp(prefix='update-', dir=STATE))
    host = stage / 'host'
    print(f'Staging system update in {stage}', flush=True)
    shutil.copytree(source, host, ignore=shutil.ignore_patterns('.git'), symlinks=False)
    lock = source / 'flake.lock'
    old_lock = lock.read_bytes() if lock.exists() else None
    if old_lock is not None:
        (stage / 'previous-flake.lock').write_bytes(old_lock)
    try:
        # Override the rolling input rather than independently upgrading its
        # dependency graph. The upstream Sleepy lock pins compatible components.
        run(NIX + ['flake', 'lock', '--refresh', '--override-input', config['input'],
                   config['source'], '--output-lock-file', str(host / 'flake.lock'), str(host)])
        pinned = json.loads((host / 'flake.lock').read_text())
        selected = pinned.get('nodes', {}).get(pinned.get('root'), {}).get('inputs', {}).get(config['input'])
        if not isinstance(selected, str) or selected not in pinned.get('nodes', {}):
            raise SnugError('Configured rolling input must be a direct input of the host flake.')
        run(NIX + ['build', '--no-update-lock-file', '--out-link', str(stage / 'result'),
                   str(host) + '#nixosConfigurations.' + config['host'] + '.config.system.build.toplevel'])
        target = store_system(stage / 'result')
        new_lock = (host / 'flake.lock').read_bytes()
        if target == previous_system:
            # nix-env does not create a generation for an identical target.
            # Keep that generation's original lock and rollback receipt intact.
            # A newer upstream lock yielding the same system can be retried on
            # the next update without breaking the generation/lock history.
            print(f'System is already generation {previous_number}; no configuration changed. '
                  'The host lock and rollback history were preserved.')
            return 0
        activate(target, previous_number, previous_system)
        try:
            number, _ = current_generation()
            receipt = dict(previous=previous_number, flake=str(source),
                           oldLock=None if old_lock is None else old_lock.decode('utf-8'),
                           newLockHash=hashlib.sha256(new_lock).hexdigest())
            atomic_write(STATE / f'generation-{number}.json', json.dumps(receipt).encode())
            atomic_write(lock, new_lock)
        except (OSError, ValueError, KeyboardInterrupt):
            restore(previous_number, previous_system)
            raise
    except (subprocess.CalledProcessError, OSError, ValueError, SnugError, KeyboardInterrupt):
        print(f'snug: update failed; staging files retained at {stage}.', file=sys.stderr)
        raise
    print(f'System updated to generation {number}. Previous generations remain available.')
    return 0


def rollback():
    number, current = current_generation()
    candidates = []
    for entry in PROFILE.parent.glob('system-*-link'):
        match = re.fullmatch(r'system-([0-9]+)-link', entry.name)
        if match and int(match[1]) < number and entry.exists():
            candidates.append(int(match[1]))
    if not candidates:
        raise SnugError('No previous NixOS generation is available.')
    receipt_path = STATE / f'generation-{number}.json'
    receipt = None
    if receipt_path.exists():
        trusted(receipt_path)
        receipt = json.loads(receipt_path.read_text())
        previous = receipt.get('previous')
        if type(previous) is not int or previous not in candidates:
            raise SnugError('The recorded previous system generation is unavailable; select a known working generation from the boot menu.')
    else:
        previous = max(candidates)
    target = store_system(PROFILE.parent / f'system-{previous}-link')
    lock = None
    old_lock = None
    if receipt is not None:
        candidate = Path(receipt['flake']) / 'flake.lock'
        try:
            trusted(candidate)
            current_lock = candidate.read_bytes()
        except FileNotFoundError:
            print('Host flake.lock is missing; rolling back the OS without recreating it.')
        else:
            if hashlib.sha256(current_lock).hexdigest() == receipt['newLockHash']:
                lock = candidate
                old_lock = receipt['oldLock']
            else:
                print('Host flake.lock has changed since the update; preserving your current source lock.')
    activate(target, number, current, generation=previous)
    if lock is not None:
        try:
            if old_lock is None:
                lock.unlink()
            else:
                atomic_write(lock, old_lock.encode('utf-8'))
        except (OSError, KeyboardInterrupt):
            restore(number, current)
            raise
    print(f'System rolled back to generation {previous}. No generations were deleted.')
    return 0


def system_action(action):
    if action not in ('update', 'rollback'):
        raise SnugError('Unknown system operation.')
    if os.geteuid() != 0:
        run(['/run/wrappers/bin/sudo', '--', '/run/current-system/sw/bin/snug', action, '--system'])
        return 0
    trusted(STATE.parent, directory=True)
    STATE.mkdir(mode=0o700, exist_ok=True)
    trusted(STATE, directory=True)
    if os.path.lexists(STATE / '.lock'):
        trusted(STATE / '.lock')
    with mutation_lock(STATE):
        return update() if action == 'update' else rollback()
