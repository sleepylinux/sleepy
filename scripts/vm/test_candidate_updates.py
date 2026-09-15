"""Candidate-runner checks; no VM boot or update commands are executed here."""
import importlib.util
from pathlib import Path
import subprocess
import contextlib
import io
import json
import os
import sys
import time
from unittest.mock import patch
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location('candidate_updates', Path(__file__).with_name('candidate_updates.py'))


class CandidateProtocol(unittest.TestCase):
    def module(self):
        self.assertTrue(Path(SPEC.origin).exists(), 'candidate protocol is missing')
        module = importlib.util.module_from_spec(SPEC)
        SPEC.loader.exec_module(module)
        return module

    def test_parameters_are_paired_immutable_and_exclusive(self):
        m = self.module()
        good = 'sha256-' + 'A' * 43 + '='
        m.validate('a' * 40, good, False, False)
        m.validate(None, None, False, False)
        for rev, digest, update, recovery in [
            ('main', good, False, False), ('a' * 40, None, False, False),
            (None, good, False, False), ('a' * 40, good, True, False),
            ('a' * 40, good, False, True), ('a' * 40, 'sha256-bad', False, False),
        ]:
            with self.subTest(rev=rev, digest=digest, update=update, recovery=recovery):
                with self.assertRaises(ValueError): m.validate(rev, digest, update, recovery)

    def test_cli_rejects_incompatible_mode_before_touching_output(self):
        runner = Path(__file__).with_name('installable-alpha.py')
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / 'must-not-exist'
            for flag in ('--update-safety', '--boot-recovery'):
                result = subprocess.run([sys.executable, str(runner), '--iso', '/nonexistent',
                    '--output', str(output), '--candidate-revision', 'a' * 40,
                    '--candidate-nar-hash', 'sha256-' + 'A' * 43 + '=', flag],
                    text=True, capture_output=True, timeout=10)
                self.assertEqual(result.returncode, 2)
                self.assertIn('separate scenarios', result.stderr)
                self.assertFalse(output.exists())

    def test_tree_fingerprint_detects_data_mode_and_symlink_changes(self):
        m = self.module()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            file = root / 'configuration.nix'; file.write_text('original')
            before = m.tree_state(root)
            file.write_text('changed'); self.assertNotEqual(before, m.tree_state(root))
            file.write_text('original'); self.assertEqual(before, m.tree_state(root))
            file.chmod(0o600); self.assertNotEqual(before, m.tree_state(root))
            link = root / 'link'; link.symlink_to('configuration.nix')
            before = m.tree_state(root); link.unlink(); link.symlink_to('other')
            self.assertNotEqual(before, m.tree_state(root))

    def test_failed_prepare_that_changes_boot_cannot_reach_successful_prepare(self):
        m = self.module()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            def guest_path(value, *parts):
                return root / str(value).lstrip('/') / Path(*parts)
            for name in ('run/current-system/etc/sleepy', 'nix/var/nix/profiles',
                         'etc/nixos', 'boot/loader', 'var/lib/sleepy-alpha', 'nix/store/original-source'):
                (root / name).mkdir(parents=True, exist_ok=True)
            (root / 'nix/store/original-source/flake.nix').write_text('{}')
            source = {'schema': 1, 'source_path': '/nix/store/original-source',
                      'nar_hash': 'sha256-' + 'A' * 43 + '=', 'revision': 'b' * 40}
            (root / 'run/current-system/etc/sleepy/source.json').write_text(json.dumps(source))
            (root / 'nix/var/nix/profiles/system').symlink_to(root / 'run/current-system')
            (root / 'etc/nixos/configuration.nix').write_text('{}')
            boot = root / 'boot/loader/loader.conf'; boot.write_text('original')
            calls = []; statuses = iter(('idle', 'failed'))
            def execute(argv, **kwargs):
                calls.append(argv)
                output = ''; code = 0
                if argv[1] == 'source': output = source['source_path']
                elif argv[1] == 'status': output = json.dumps({'phase': next(statuses)})
                elif argv[1] == 'candidates':
                    catalog = root / 'etc/sleepy/candidates'
                    output = json.dumps([json.loads(p.read_text()) for p in sorted(catalog.glob('*.json'))])
                elif argv[1:] == ('prepare', 'vm-wrong-hash'):
                    boot.write_text('unexpected modification'); code = 1
                else: self.fail('unexpected command: ' + repr(argv))
                return subprocess.CompletedProcess(argv, code, output)
            original_stat = Path.stat
            def root_stat(path, *args, **kwargs):
                values = list(original_stat(path, *args, **kwargs)); values[4] = 0
                return os.stat_result(values)
            with patch.object(m, 'Path', guest_path), patch.object(Path, 'stat', root_stat), patch.object(m.subprocess, 'run', execute), contextlib.redirect_stdout(io.StringIO()):
                with self.assertRaises(AssertionError):
                    m.guest('prepare', 'a' * 40, 'sha256-' + 'A' * 43 + '=')
            self.assertNotIn(('sleepy-update', 'prepare', 'vm-reviewed'), calls)
            self.assertEqual(calls[-1], ('sleepy-update', 'status'))

    def test_temporary_configuration_restores_exact_original_after_failure(self):
        m = self.module()
        self.assertTrue(hasattr(m, 'temporary_configuration'), 'temporary configuration helper missing')
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            original = config / 'configuration.nix'
            original.write_bytes(b'{ ... }: { imports = [ ./hardware.nix ]; }\n')
            original.chmod(0o640)
            before = m.tree_state(config)
            with self.assertRaisesRegex(RuntimeError, 'build rejected'):
                with m.temporary_configuration(config, 'assertions = [];'):
                    self.assertIn('imports = [ ./candidate-original.nix ];', original.read_text())
                    self.assertEqual((config / 'candidate-original.nix').read_bytes(), b'{ ... }: { imports = [ ./hardware.nix ]; }\n')
                    raise RuntimeError('build rejected')
            self.assertEqual(m.tree_state(config), before)

    def test_temporary_configuration_refuses_existing_backup(self):
        m = self.module()
        self.assertTrue(hasattr(m, 'temporary_configuration'), 'temporary configuration helper missing')
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory)
            (config / 'configuration.nix').write_text('original')
            (config / 'candidate-original.nix').write_text('existing')
            before = m.tree_state(config)
            with self.assertRaises(AssertionError):
                with m.temporary_configuration(config, 'assertions = [];'): pass
            self.assertEqual(m.tree_state(config), before)

    def test_interruption_observes_real_argv0_and_reaps_builder(self):
        m = self.module()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            marker = 'SLEEPY_TEST_' + os.urandom(12).hex()
            worker = (
                'import os,signal,subprocess,sys,time\n'
                'time.sleep(0.4)\n'
                "child=subprocess.Popen(['bash','-c',sys.argv[1]], start_new_session=True)\n"
                'def stop(*_):\n'
                ' os.killpg(child.pid,signal.SIGTERM); child.wait(timeout=2); sys.exit(1)\n'
                'signal.signal(signal.SIGTERM, stop)\n'
                'child.wait()\n')
            original_popen = subprocess.Popen
            children = []
            def spawn(argv, **kwargs):
                self.assertEqual(argv, ['sleepy-update', 'prepare', 'vm-reviewed'])
                self.assertFalse('env' in kwargs, 'must preserve the ordinary backend environment')
                child = original_popen([sys.executable, '-c', worker, m.builder_command(marker, '/bin/bash')], **kwargs)
                children.append(child)
                return child
            started = time.monotonic()
            with patch.object(m.subprocess, 'Popen', spawn), contextlib.redirect_stdout(io.StringIO()):
                m.interrupt_build(root, marker)
            self.assertGreaterEqual(time.monotonic() - started, 0.4)
            self.assertEqual(len(children), 1)
            self.assertEqual(children[0].returncode, 1)
            self.assertEqual(m.marker_processes(marker), set())

    def test_controlled_builder_uses_shell_as_argv0_carrier(self):
        m = self.module()
        self.assertTrue(hasattr(m, 'builder_command'), 'fixed controlled builder command missing')
        marker = 'SLEEPY_TEST_' + os.urandom(12).hex()
        command = m.builder_command(marker, '/bin/bash')
        process = subprocess.Popen(['/bin/bash', '-c', command], start_new_session=True)
        try:
            deadline = time.monotonic() + 3
            while process.pid not in m.marker_processes(marker) and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertIn(process.pid, m.marker_processes(marker))
            with Path('/proc', str(process.pid), 'cmdline').open('rb') as stream:
                self.assertEqual(stream.read(1024).split(b'\0')[:3], [marker.encode(), b'-c', b'sleep 600; :'])
        finally:
            import signal
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=3)
        self.assertEqual(m.marker_processes(marker), set())

    def test_process_observer_requires_exact_first_cmdline_field(self):
        m = self.module()
        self.assertTrue(hasattr(m, 'marker_processes'), 'process observer missing')
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            for pid, data in [(101, b'unique\0sleep\0'), (102, b'python\0unique\0'),
                              (103, b'unique-suffix\0'), (104, b'')]:
                (proc / str(pid)).mkdir()
                (proc / str(pid) / 'cmdline').write_bytes(data)
            self.assertEqual(m.marker_processes('unique', proc), {101})

    def test_all_guest_phases_compile_and_shell_parse(self):
        m = self.module()
        for phase in ('prepare', 'rollback', 'verify'):
            script = m.fixture(phase, 'a' * 40, 'sha256-' + 'A' * 43 + '=')
            subprocess.run(['bash', '-n'], input=script, text=True, check=True)
            compile(script.split("<<'SLEEPY_CANDIDATE_PY'\n", 1)[1].rsplit('\nSLEEPY_CANDIDATE_PY', 1)[0], '<guest>', 'exec')
        self.assertEqual(m.fixture(None, None, None), '')
        with self.assertRaises(ValueError): m.fixture('unknown', 'a' * 40, 'sha256-' + 'A' * 43 + '=')


if __name__ == '__main__': unittest.main()
