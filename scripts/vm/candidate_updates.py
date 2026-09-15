"""Explicit local candidate catalog fixture for disposable installed VMs only."""
import base64
import hashlib
import inspect
import json
from pathlib import Path
import re
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
    program = 'import base64, hashlib, json, stat, subprocess\nfrom pathlib import Path\n'
    program += inspect.getsource(tree_state) + '\n' + inspect.getsource(guest)
    program += '\nguest(' + ', '.join(repr(x) for x in (phase, revision, nar_hash)) + ')\n'
    return '\n"$python" - <<\'SLEEPY_CANDIDATE_PY\'\n' + program + 'SLEEPY_CANDIDATE_PY\n'
