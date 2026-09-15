"""Explicit local candidate catalog fixture for disposable installed VMs only."""
import base64
import contextlib
import os
import time
import uuid
import hashlib
import inspect
import json
from pathlib import Path
import re
import shlex
import stat
import subprocess


def validate(revision, nar_hash, update_safety=False, boot_recovery=False):
    if revision is None and nar_hash is None:
        return
    if update_safety or boot_recovery:
        raise ValueError('candidate updates, update-safety and boot-recovery are separate scenarios')
    if not revision or not re.fullmatch(r'[0-9a-f]{40}', revision):
        raise ValueError('--candidate-revision requires an exact lowercase 40-character commit')
    if not nar_hash or not re.fullmatch(r'sha256-[A-Za-z0-9+/]{43}=', nar_hash):
        raise ValueError('--candidate-nar-hash requires SHA256 SRI')
    if base64.b64encode(base64.b64decode(nar_hash[7:], validate=True)).decode() != nar_hash[7:]:
        raise ValueError('candidate NAR hash must be canonical SRI')


def tree_state(root):
    """Record file contents, permissions and link targets without following links."""
    result = {}
    for path in sorted(root.rglob('*')):
        mode = path.lstat().st_mode
        if stat.S_ISLNK(mode):
            value = ('link', str(path.readlink()))
        elif stat.S_ISREG(mode):
            with path.open('rb') as stream:
                value = ('file', hashlib.file_digest(stream, 'sha256').hexdigest())
        elif stat.S_ISDIR(mode):
            value = ('directory',)
        else:
            raise RuntimeError(f'Unexpected fixture filesystem entry: {path}')
        result[str(path.relative_to(root))] = [stat.S_IMODE(mode), *value]
    return result


@contextlib.contextmanager
def temporary_configuration(config, options):
    """Import the original module at the same depth; restore its inode on all exits."""
    original = config / 'configuration.nix'
    backup = config / 'candidate-original.nix'
    assert original.is_file() and not original.is_symlink()
    assert not backup.exists() and not backup.is_symlink(), 'fixture backup already exists'
    original.rename(backup)
    try:
        with original.open('x') as stream:
            stream.write('{ pkgs, ... }: { imports = [ ./candidate-original.nix ];\n' + options + '\n}\n')
        original.chmod(0o600)
        yield
    finally:
        backup.replace(original)


def marker_processes(marker, proc=Path('/proc')):
    """Read only argv[0], never expose other processes' arguments in evidence."""
    matches = set()
    with os.scandir(proc) as entries:
        for count, entry in enumerate(entries):
            if count >= 32768:
                raise RuntimeError('process observation exceeded its entry bound')
            if not entry.name.isdecimal():
                continue
            try:
                with (proc / entry.name / 'cmdline').open('rb') as stream:
                    first = stream.read(256).split(b'\0', 1)[0]
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue
            if first == marker.encode():
                matches.add(int(entry.name))
    return matches


def builder_command(marker, bash):
    # Coreutils may dispatch by argv[0], so the marker belongs to Bash. The
    # trailing builtin prevents Bash from replacing itself with multicall sleep.
    return 'exec -a ' + shlex.quote(marker) + ' ' + shlex.quote(bash) + " -c 'sleep 600; :'"


def interrupt_build(state, marker):
    """Interrupt only after observing this attempt's actual controlled builder."""
    assert not marker_processes(marker), 'controlled builder already exists'
    output_path = state / 'interrupted-prepare.log'
    with output_path.open('x') as output:
        output_path.chmod(0o600)
        process = subprocess.Popen(['sleepy-update', 'prepare', 'vm-reviewed'],
                                   stdout=output, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 180
            observed = set()
            while time.monotonic() < deadline:
                observed = marker_processes(marker)
                if observed:
                    break
                if process.poll() is not None:
                    raise RuntimeError('prepare exited before the controlled builder appeared')
                time.sleep(0.25)
            assert len(observed) == 1, 'one real controlled Nix builder must start within deadline'
            assert process.poll() is None, 'backend exited before interruption'
            print('CANDIDATE_CONTROLLED_BUILD_STARTED', flush=True)
            process.terminate()
            assert process.wait(timeout=20) == 1, 'SIGTERM did not produce a reaped failed prepare'
            deadline = time.monotonic() + 20
            while marker_processes(marker) and time.monotonic() < deadline:
                time.sleep(0.25)
            assert not marker_processes(marker), 'controlled builder survived backend cancellation'
        finally:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=20)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            output.flush()
            print(output_path.read_text()[-65536:], end='', flush=True)


def guest(phase, revision, nar_hash):
    state = Path('/var/lib/sleepy-alpha/candidate-update')
    metadata = Path('/run/current-system/etc/sleepy/source.json')
    profile = Path('/nix/var/nix/profiles/system')
    live = Path('/run/current-system')
    config = Path('/etc/nixos')

    def command(*argv, timeout=120, ok=True):
        result = subprocess.run(argv, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=timeout)
        print(result.stdout, end='', flush=True)
        if ok and result.returncode != 0:
            raise RuntimeError(f'{argv[0]} failed: {result.returncode}')
        return result

    def read_source():
        value = json.loads(metadata.read_text())
        assert value['schema'] == 1 and value['source_path'].startswith('/nix/store/')
        assert value['nar_hash'].startswith('sha256-')
        assert Path(value['source_path'], 'flake.nix').is_file()
        resolved = command('sleepy-update', 'source').stdout.strip()
        assert resolved == value['source_path'], 'source resolver disagrees with booted metadata'
        return value

    def config_unchanged(saved):
        assert tree_state(config) == saved['config'], 'saved installation configuration changed'

    def save(value):
        (state / 'before.json').write_text(json.dumps(value))

    if phase == 'prepare':
        assert not state.exists(), 'candidate fixture must start fresh'
        state.mkdir(mode=0o700)
        source = read_source()
        assert source.get('revision') != revision, 'candidate must differ from installed source'
        before = {'source': source, 'live': str(live.resolve()), 'profile': str(profile.resolve()),
                  'profile_link': str(profile.readlink()), 'boot': tree_state(Path('/boot')), 'config': tree_state(config)}
        save(before)
        assert json.loads(command('sleepy-update', 'status').stdout)['phase'] == 'idle'
        assert json.loads(command('sleepy-update', 'candidates', '--json').stdout) == [], 'expected default-empty catalog'
        catalog = Path('/etc/sleepy/candidates')
        catalog.mkdir(parents=True, exist_ok=True)
        assert not catalog.is_symlink(), 'test catalog must be a writable real directory'
        # Explicit root-owned VM fixture, never a public promotion/catalog.
        wrong = base64.b64encode(bytes([base64.b64decode(nar_hash[7:])[0] ^ 1]) + base64.b64decode(nar_hash[7:])[1:]).decode()
        for identifier, digest in [('vm-wrong-hash', 'sha256-' + wrong), ('vm-reviewed', nar_hash)]:
            path = catalog / (identifier + '.json')
            with path.open('x') as stream:
                json.dump({'schema': 1, 'id': identifier, 'version': 'VM fixture', 'revision': revision, 'nar_hash': digest}, stream)
            path.chmod(0o644)
            assert path.stat().st_uid == 0
        candidates = json.loads(command('sleepy-update', 'candidates', '--json').stdout)
        assert {item['id'] for item in candidates} == {'vm-wrong-hash', 'vm-reviewed'}
        rejected = command('sleepy-update', 'prepare', 'vm-wrong-hash', timeout=300, ok=False)
        assert rejected.returncode == 1, 'incorrect source hash must be rejected'
        assert json.loads(command('sleepy-update', 'status').stdout)['phase'] == 'failed'
        assert str(profile.resolve()) == before['profile'] and str(profile.readlink()) == before['profile_link']
        assert str(live.resolve()) == before['live']
        assert tree_state(Path('/boot')) == before['boot']
        config_unchanged(before)
        print('CANDIDATE_WRONG_HASH_PRESERVED_BOOT_CONFIG_OK', flush=True)
        def unchanged_after_failed_prepare():
            assert json.loads(command('sleepy-update', 'status').stdout)['phase'] == 'failed'
            assert str(profile.resolve()) == before['profile'] and str(profile.readlink()) == before['profile_link']
            assert str(live.resolve()) == before['live']
            assert tree_state(Path('/boot')) == before['boot']
            config_unchanged(before)

        assert (config / 'configuration.nix').stat().st_uid == 0
        invalid_marker = 'SLEEPY_CANDIDATE_INVALID_CONFIGURATION'
        with temporary_configuration(config, 'assertions = [ { assertion = false; message = "' + invalid_marker + '"; } ];'):
            rejected = command('sleepy-update', 'prepare', 'vm-reviewed', timeout=300, ok=False)
            assert rejected.returncode == 1, 'invalid configuration unexpectedly prepared'
            # Require the actual evaluator assertion, not an unrelated fetch error.
            assert invalid_marker in Path('/var/lib/sleepy-update/update.log').read_text()
        unchanged_after_failed_prepare()
        print('CANDIDATE_INVALID_CONFIG_PRESERVED_BOOT_CONFIG_OK', flush=True)

        build_marker = 'SLEEPY_CANDIDATE_BUILD_' + uuid.uuid4().hex
        controlled_build = ("system.extraDependencies = [ (pkgs.runCommand \"sleepy-candidate-interrupt\" {} ''"
                            + builder_command(build_marker, "${pkgs.bash}/bin/bash") + "\n'' ) ];")
        with temporary_configuration(config, controlled_build):
            interrupt_build(state, build_marker)
        unchanged_after_failed_prepare()
        print('CANDIDATE_SIGTERM_PRESERVED_BOOT_CONFIG_OK', flush=True)
        command('sleepy-update', 'prepare', 'vm-reviewed', timeout=1500)
        status = json.loads(command('sleepy-update', 'status').stdout)
        assert status['phase'] == 'ready' and status['candidate']['revision'] == revision
        assert status['candidate']['nar_hash'] == nar_hash
        assert str(live.resolve()) == before['live']
        config_unchanged(before)
        prepared = str(profile.resolve())
        assert prepared != before['profile'] and status['built'] == prepared
        target = json.loads((profile / 'etc/sleepy/source.json').read_text())
        assert target['nar_hash'] == nar_hash and target['source_path'].startswith('/nix/store/')
        before['prepared'] = prepared
        save(before)
        print('CANDIDATE_PREPARED_WITHOUT_LIVE_OR_CONFIG_CHANGE_OK', flush=True)
        return

    before = json.loads((state / 'before.json').read_text())
    config_unchanged(before)
    source = read_source()
    if phase == 'rollback':
        assert str(live.resolve()) == before['prepared']
        assert source['nar_hash'] == nar_hash
        visible_status = command('sleepy-system', 'status').stdout
        assert 'Sleepy version: ' + source['version'] in visible_status
        assert 'Source NAR: ' + nar_hash[:19] in visible_status
        print('CANDIDATE_REAL_PASSWORD_BOOT_SOURCE_OK', flush=True)
        # Exercise the booted candidate's cleanup implementation, not the old
        # installer backend used for the first preparation.
        update_state = Path('/var/lib/sleepy-update')
        previous_roots = {str(path): str(path.readlink()) for path in update_state.glob('attempt-*/built-system') if path.is_symlink()}
        selected_link = str(profile.readlink())
        command('sleepy-update', 'prepare', 'vm-reviewed', timeout=1500)
        ready = json.loads(command('sleepy-update', 'status').stdout)
        assert ready['phase'] == 'ready' and ready['built'] == before['prepared']
        completed_root = Path(ready['gc_root'])
        assert completed_root.parent.is_dir()
        assert not completed_root.exists() and not completed_root.is_symlink(), 'completed attempt GC root was retained'
        assert str(profile.readlink()) == selected_link, 'same candidate added a generation'
        assert str(live.resolve()) == before['prepared']
        assert {str(path): str(path.readlink()) for path in update_state.glob('attempt-*/built-system') if path.is_symlink()} == previous_roots
        config_unchanged(before)
        print('CANDIDATE_COMPLETED_GC_ROOT_RELEASED_OTHERS_PRESERVED_OK', flush=True)
        command('sleepy-system', 'rebuild', timeout=1500)
        config_unchanged(before)
        rebuilt = json.loads((profile / 'etc/sleepy/source.json').read_text())
        assert rebuilt == source, 'saved rebuild drifted from booted candidate source'
        assert str(profile.resolve()) == before['prepared'], 'unchanged saved rebuild changed generation output'
        print('CANDIDATE_SAVED_REBUILD_STAYS_CANDIDATE_OK', flush=True)
        command('sleepy-system', 'rollback', timeout=120)
        assert str(profile.resolve()) == before['profile'], 'rollback did not select original system'
        config_unchanged(before)
        print('CANDIDATE_ORIGINAL_SELECTED_FOR_BOOT_OK', flush=True)
    elif phase == 'verify':
        assert str(live.resolve()) == before['live']
        assert source == before['source'], 'rollback source metadata differs from original'
        command('sleepy-system', 'rebuild', timeout=1500)
        config_unchanged(before)
        rebuilt = json.loads((profile / 'etc/sleepy/source.json').read_text())
        assert rebuilt['nar_hash'] == before['source']['nar_hash']
        assert rebuilt['source_path'] == before['source']['source_path'], 'saved rebuild drifted after rollback'
        print('CANDIDATE_ROLLBACK_PASSWORD_BOOT_AND_SAVED_REBUILD_OK', flush=True)
    else:
        raise ValueError('unknown candidate phase')


def fixture(phase, revision, nar_hash):
    if phase is None:
        return ''
    validate(revision, nar_hash)
    if phase not in ('prepare', 'rollback', 'verify'):
        raise ValueError('unknown candidate phase')
    program = 'import base64, contextlib, hashlib, json, os, shlex, stat, subprocess, time, uuid\nfrom pathlib import Path\n'
    program += '\n'.join(inspect.getsource(function) for function in (tree_state, temporary_configuration, marker_processes, builder_command, interrupt_build, guest))
    program += '\nguest(' + ', '.join(repr(x) for x in (phase, revision, nar_hash)) + ')\n'
    return '\n"$python" - <<\'SLEEPY_CANDIDATE_PY\'\n' + program + 'SLEEPY_CANDIDATE_PY\n'
