#!/usr/bin/env python3
"""Snug: small, explicit Nix workflows for Sleepy Linux."""
import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

SOURCE = 'github:NixOS/nixpkgs/nixos-unstable'
ACTIONS = {'-i': 'install', '-r': 'remove', '-s': 'search', '-l': 'list',
           '-u': 'update', '-b': 'rollback', '-x': 'run', '-e': 'shell',
           '-d': 'dev', '--doctor': 'doctor'}
ACTIONS.update({'--' + name: name for name in ACTIONS.values()})
ACTIONS['--nix'] = 'nix'
ACTIONS['--refresh'] = 'refresh'
NIX = ['nix', '--extra-experimental-features', 'nix-command flakes']


class SnugError(Exception):
    pass


def run(args, **kwargs):
    """Never evaluate a shell; preserve the backend's failure status."""
    return subprocess.run(args, check=True, **kwargs)


def package(name):
    if not re.fullmatch(r'[A-Za-z0-9_][A-Za-z0-9_+.-]*', name):
        raise SnugError(f'Invalid package name: {name!r}. Use a nixpkgs name such as vim or python3Packages.requests.')
    return SOURCE + '#' + name


def state_dir():
    base = os.environ.get('XDG_STATE_HOME') or str(Path.home() / '.local/state')
    if not Path(base).is_absolute():
        raise SnugError('XDG_STATE_HOME must be an absolute path.')
    return Path(base) / 'snug'


@contextmanager
def mutation_lock(directory):
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(directory / '.lock', os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SnugError('Another snug operation is running. Wait for it to finish.') from None
        yield
    finally:
        os.close(fd)


def parser():
    p = argparse.ArgumentParser(prog='snug', description='Packages, development environments and rolling Sleepy updates.',
                                formatter_class=argparse.RawDescriptionHelpFormatter,
                                epilog='''Short and long forms:
  -i, --install      -r, --remove       -s, --search
  -l, --list         -u, --update       -b, --rollback
  -x, --run          -e, --shell        -d, --dev
  -it = --install --temporary: packages available in a temporary shell
  --unfree: allow unfree packages for this personal operation only

Examples:
  snug -i vim                  install for this user
  snug -i --unfree steam       explicitly allow an unfree package
  snug -it vim                 temporarily use vim; exit to leave
  snug -it git -- git --version run one command with temporary tools
  snug -u                      update personal packages
  snug -u --system             update rolling Sleepy OS
  snug -d init python          create a locked dev environment
  snug nix flake show          access any underlying Nix capability

Guide: docs/snug.md (also installed under share/doc/snug/).''')
    p.add_argument('--version', action='version', version='snug 0.1.0')
    sub = p.add_subparsers(dest='action', required=True)
    for action, flag in [('install', '-i'), ('remove', '-r'), ('search', '-s')]:
        cmd = sub.add_parser(action, help=f'{flag}  {action} packages')
        cmd.add_argument('packages', nargs='+')
        if action in ('install', 'search'):
            cmd.add_argument('--unfree', action='store_true', help='allow unfree packages for this command using impure Nix evaluation')
        if action == 'install':
            cmd.add_argument('-t', '--temporary', action='store_true', help='enter a temporary shell instead of modifying your profile')
    cmd = sub.add_parser('list', help='-l  list personal packages')
    cmd.add_argument('--json', action='store_true')
    for action, flag in [('update', '-u'), ('rollback', '-b')]:
        cmd = sub.add_parser(action, help=f'{flag}  {action} personal packages (or --system)')
        cmd.add_argument('--system', action='store_true')
        if action == 'update':
            cmd.add_argument('--unfree', action='store_true', help='allow unfree packages during this personal profile update')
    cmd = sub.add_parser('run', help='-x  run a package without installing it')
    cmd.add_argument('--unfree', action='store_true', help='allow an unfree package; place before the package name')
    cmd.add_argument('package')
    cmd.add_argument('arguments', nargs=argparse.REMAINDER)
    cmd = sub.add_parser('shell', help='-e  temporary tools; optional -- command args')
    cmd.add_argument('--unfree', action='store_true', help='allow unfree packages in this temporary environment')
    cmd.add_argument('packages', nargs='+')
    cmd = sub.add_parser('dev', help='-d  enter a project; init PRESET [DIRECTORY] or update')
    cmd.add_argument('arguments', nargs=argparse.REMAINDER)
    cmd = sub.add_parser('nix', help='pass any arguments directly to Nix (advanced)')
    cmd.add_argument('arguments', nargs=argparse.REMAINDER)
    sub.add_parser('refresh', help='refresh launcher entries after resolving a desktop-directory conflict')
    sub.add_parser('doctor', help='--doctor  diagnose setup')
    sub.add_parser('generations', help='list personal profile history')
    return p



def removal_names(profile, requested):
    result = run(NIX + ['profile', 'list', '--profile', profile, '--json'], capture_output=True, text=True)
    elements = json.loads(result.stdout).get('elements', {})
    if not isinstance(elements, dict):
        raise SnugError('Unsupported Nix profile manifest; inspect it with snug nix profile list.')
    names = []
    for requested_name in requested:
        if requested_name in elements:
            names.append(requested_name)
            continue
        matches = []
        for name, metadata in elements.items():
            attr = metadata.get('attrPath', '')
            parts = attr.split('.', 2)
            attr = parts[2] if len(parts) == 3 and parts[0] in ('packages', 'legacyPackages') else attr
            if attr == requested_name:
                matches.append(name)
        if len(matches) != 1:
            raise SnugError(f'{requested_name}: not installed by snug or ambiguous. Use snug -l for exact profile names; system packages are managed in /etc/nixos/configuration.nix.')
        names.append(matches[0])
    return list(dict.fromkeys(names))


def doctor():
    ok = True
    for executable in ['nix']:
        found = shutil.which(executable)
        print(f'{executable}: {found or "MISSING — install Nix first"}')
        ok = ok and bool(found)
    profile = state_dir() / 'profile'
    print(f'Personal profile: {profile}')
    for name, entry in [('PATH', str(profile / 'bin')), ('XDG_DATA_DIRS', str(profile / 'share'))]:
        present = entry in os.environ.get(name, '').split(os.pathsep)
        print(f'{name}: {"ready" if present else "missing " + entry + " — log in again after enabling Sleepy snug integration"}')
    config = Path('/etc/snug/system.json')
    print('System updates: ' + ('configured' if config.is_file() else 'not configured; see docs/snug.md'))
    return 0 if ok else 1


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    if argv and argv[0] in ('-it', '-ti'):
        argv = ['install', '--temporary'] + argv[1:]
    if argv and argv[0] in ACTIONS:
        argv[0] = ACTIONS[argv[0]]
    if argv and argv[0] == 'nix':
        run(NIX + (argv[1:] or ['--help']))
        return 0
    temporary = argv and argv[0] == 'install' and any(a in ('--temporary', '-t') for a in argv[1:argv.index('--') if '--' in argv else len(argv)])
    # Capture command argv separately so argparse cannot consume a command flag.
    command = []
    if argv and (argv[0] == 'shell' or temporary) and '--' in argv:
        boundary = argv.index('--')
        command, argv = argv[boundary + 1:], argv[:boundary]
        if not command:
            raise SnugError('Supply a command after --, or omit -- for an interactive shell.')
    args = parser().parse_args(argv)
    allow_unfree = getattr(args, 'unfree', False)
    if allow_unfree and getattr(args, 'system', False):
        raise SnugError('--unfree applies to personal packages; configure system licensing in /etc/nixos/configuration.nix.')
    evaluation_flags = ['--impure'] if allow_unfree else []
    # Never export this opt-in into the caller or later Snug operations.
    evaluation_options = {'env': dict(os.environ, NIXPKGS_ALLOW_UNFREE='1')} if allow_unfree else {}
    if args.action == 'nix':
        run(NIX + ['--help'])
        return 0
    if args.action == 'install' and args.temporary:
        run(NIX + ['shell'] + evaluation_flags + [package(n) for n in args.packages] + (['--command'] + command if command else []), **evaluation_options)
        return 0
    if args.action == 'refresh':
        with mutation_lock(state_dir()):
            refresh_desktop(state_dir() / 'profile')
        return 0
    if args.action == 'doctor':
        return doctor()
    if getattr(args, 'system', False):
        from system_update import system_action
        return system_action(args.action)
    if args.action == 'dev':
        from devenv import develop
        return develop(args.arguments)
    if args.action in ('run', 'shell', 'search'):
        if args.action == 'search':
            run(NIX + ['search'] + evaluation_flags + [SOURCE, '--'] + args.packages, **evaluation_options)
        elif args.action == 'run':
            tail = args.arguments[1:] if args.arguments[:1] == ['--'] else args.arguments
            run(NIX + ['run'] + evaluation_flags + [package(args.package), '--'] + tail, **evaluation_options)
        else:
            run(NIX + ['shell'] + evaluation_flags + [package(n) for n in args.packages] + (['--command'] + command if command else []), **evaluation_options)
        return 0
    directory = state_dir()
    profile = str(directory / 'profile')
    if args.action == 'install':
        # Validate every argument before creating state or executing a backend.
        operation = ['install'] + [package(n) for n in args.packages]
    elif args.action == 'remove':
        for name in args.packages:
            package(name)
        operation = ['remove', '--'] + args.packages
    elif args.action == 'update':
        operation = ['upgrade', '--all', '--refresh']
    elif args.action == 'rollback':
        operation = ['rollback']
    elif args.action == 'list':
        operation = ['list'] + (['--json'] if args.json else [])
    else:
        operation = ['history']
    if args.action in ('list', 'generations'):
        if not (directory / 'profile').exists():
            print('{}' if getattr(args, 'json', False) else 'No snug packages yet. Try: snug -i vim')
            return 0
        run(NIX + ['profile'] + operation + ['--profile', profile])
    else:
        with mutation_lock(directory):
            if args.action == 'remove':
                operation = ['remove', '--'] + removal_names(profile, args.packages)
            run(NIX + ['profile', operation[0]] + evaluation_flags + ['--profile', profile] + operation[1:], **evaluation_options)
            refresh_desktop(Path(profile))
    return 0


def refresh_desktop(profile):
    from desktop_entries import DesktopSyncError, sync
    try:
        sync(profile)
    except DesktopSyncError as error:
        raise SnugError(f'Packages changed, but launcher refresh failed: {error}. Resolve the conflict and run snug refresh.') from None


def entrypoint():
    try:
        return main()
    except subprocess.CalledProcessError as error:
        print(f'snug: operation failed (exit {error.returncode}); inspect the Nix diagnostic above.', file=sys.stderr)
        return error.returncode if error.returncode > 0 else 128 - error.returncode
    except (SnugError, OSError, ValueError) as error:
        print(f'snug: {error}', file=sys.stderr)
        return 1
    except KeyboardInterrupt:
        print('\nsnug: interrupted.', file=sys.stderr)
        return 130


if __name__ == '__main__':
    sys.modules['snug'] = sys.modules[__name__]
    sys.exit(entrypoint())
