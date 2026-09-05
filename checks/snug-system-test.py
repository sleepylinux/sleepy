#!/usr/bin/env python3
"""System updates against disposable files and a mocked process boundary."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'packages/snug'))
import snug
import system_update as system

NEW_LOCK = json.dumps({'version': 7, 'root': 'root', 'nodes': {
    'root': {'inputs': {'sleepy': 'sleepy'}},
    'sleepy': {'locked': {'type': 'github', 'owner': 'sleepylinux', 'repo': 'sleepy', 'rev': 'a' * 40}}}})


class SystemTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.flake = self.root / 'host'
        self.flake.mkdir()
        (self.flake / 'flake.nix').write_text('trusted host configuration')
        (self.flake / 'flake.lock').write_text('old lock')
        self.config = self.root / 'system.json'
        self.config.write_text(json.dumps(dict(flake=str(self.flake), host='sleepy',
                                               input='sleepy', source='github:sleepylinux/sleepy')))
        self.store = self.root / 'store'
        self.store.mkdir()
        self.old = self.store / 'old-system'
        self.new = self.store / 'new-system'
        self.older = self.store / 'older-system'
        for target in (self.old, self.new, self.older):
            (target / 'bin').mkdir(parents=True)
            (target / 'bin/switch-to-configuration').write_text('fake; never executed')
        self.profile = self.root / 'profiles/system'
        self.profile.parent.mkdir()
        (self.profile.parent / 'system-1-link').symlink_to(self.older)
        (self.profile.parent / 'system-2-link').symlink_to(self.old)
        self.profile.symlink_to('system-2-link')
        for name, value in dict(CONFIG=self.config, STATE=self.root / 'state', PROFILE=self.profile,
                                STORE=self.store).items():
            patcher = patch.object(system, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        # Simulate root-owned test fixtures without chown or elevated test execution.
        original = os.lstat
        def root_stat(path, *args, **kwargs):
            info = original(path, *args, **kwargs)
            fields = list(info)
            fields[4] = 0
            if Path(path) in self.root.parents:
                fields[0] &= ~0o022
            return os.stat_result(fields)
        for patcher in [patch.object(system.os, 'lstat', side_effect=root_stat),
                        patch.object(system.os, 'geteuid', return_value=0)]:
            patcher.start()
            self.addCleanup(patcher.stop)
        self.calls = []
        self.fail = None
        def execute(args, **kwargs):
            self.calls.append(args)
            if self.fail and self.fail(args):
                raise subprocess.CalledProcessError(42, args)
            if 'lock' in args:
                Path(args[-1]).joinpath('flake.lock').write_text(NEW_LOCK)
            if 'build' in args:
                Path(args[args.index('--out-link') + 1]).symlink_to(self.new)
            if '--set' in args:
                (self.profile.parent / 'system-3-link').symlink_to(self.new)
                self.profile.unlink()
                self.profile.symlink_to('system-3-link')
            if '--switch-generation' in args:
                self.profile.unlink()
                self.profile.symlink_to('system-' + args[-1] + '-link')
            return subprocess.CompletedProcess(args, 0)
        patcher = patch.object(system, 'run', side_effect=execute)
        patcher.start()
        self.addCleanup(patcher.stop)

    def test_update_builds_before_profile_and_activation_then_persists_lock(self):
        self.assertEqual(system.system_action('update'), 0)
        self.assertEqual((self.flake / 'flake.nix').read_text(), 'trusted host configuration')
        self.assertEqual((self.flake / 'flake.lock').read_text(), NEW_LOCK)
        self.assertEqual(self.profile.resolve(), self.new)
        phases = [('lock' if 'lock' in c else 'build' if 'build' in c else
                   'profile' if '--set' in c else c[-1]) for c in self.calls]
        self.assertEqual(phases, ['lock', 'build', 'dry-activate', 'profile', 'switch'])
        lock = self.calls[0]
        self.assertIn('--output-lock-file', lock)
        self.assertIn('--no-update-lock-file', self.calls[1])
        self.assertEqual(lock[lock.index('--override-input') + 1:][:2],
                         ['sleepy', 'github:sleepylinux/sleepy'])

    def test_rollback_uses_last_active_generation_not_failed_intermediate(self):
        # Generation 2 remains from a failed activation; generation 1 is active.
        self.profile.unlink()
        self.profile.symlink_to('system-1-link')
        system.system_action('update')
        self.assertEqual(self.profile.resolve(), self.new)
        self.calls.clear()
        system.system_action('rollback')
        self.assertEqual(self.profile.resolve(), self.older)
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'old lock')
        self.assertNotIn([str(self.old / 'bin/switch-to-configuration'), 'switch'], self.calls)

    def test_build_failure_preserves_profile_and_original_source(self):
        self.fail = lambda args: 'build' in args
        with self.assertRaises(subprocess.CalledProcessError):
            system.system_action('update')
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'old lock')
        self.assertFalse(any('--set' in args or args[-1] == 'switch' for args in self.calls))
        self.assertTrue(list((self.root / 'state').glob('update-*')))

    def test_dry_activation_failure_never_changes_generation(self):
        self.fail = lambda args: args[-1] == 'dry-activate'
        with self.assertRaises(subprocess.CalledProcessError):
            system.system_action('update')
        self.assertFalse(any('--set' in args for args in self.calls))
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'old lock')

    def test_activation_failure_restores_previous_generation_and_lock(self):
        self.fail = lambda args: args == [str(self.new / 'bin/switch-to-configuration'), 'switch']
        with self.assertRaises(subprocess.CalledProcessError) as caught:
            system.system_action('update')
        self.assertEqual(caught.exception.returncode, 42)
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'old lock')
        self.assertEqual(self.calls[-1], [str(self.old / 'bin/switch-to-configuration'), 'switch'])
        self.assertTrue((self.profile.parent / 'system-3-link').exists())

    def test_rollback_dry_activates_previous_generation_without_editing_lock(self):
        self.assertEqual(system.system_action('rollback'), 0)
        self.assertEqual(self.profile.resolve(), self.older)
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'old lock')
        self.assertEqual(self.calls[0], [str(self.older / 'bin/switch-to-configuration'), 'dry-activate'])
        self.assertFalse(any('build' in args or 'lock' in args for args in self.calls))

    def test_rejects_untrusted_host_tree_before_any_backend(self):
        for kind in ('writable', 'symlink'):
            with self.subTest(kind=kind):
                bad = self.flake / 'hardware.nix'
                if kind == 'writable':
                    bad.write_text('unsafe')
                    bad.chmod(0o666)
                else:
                    bad.symlink_to(self.config)
                with self.assertRaises(snug.SnugError):
                    system.system_action('update')
                bad.unlink()
                self.assertEqual(self.calls, [])

    def test_rejects_symlinked_config(self):
        self.config.unlink()
        self.config.symlink_to(self.flake / 'flake.nix')
        with self.assertRaises(snug.SnugError):
            system.system_action('update')
        self.assertEqual(self.calls, [])

    def test_update_then_rollback_restores_matching_source_lock(self):
        system.system_action('update')
        system.system_action('rollback')
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'old lock')

    def test_noop_update_preserves_generation_receipt_and_source_lock(self):
        system.system_action('update')
        receipt = self.root / 'state/generation-3.json'
        before_receipt = receipt.read_bytes()
        before_lock = (self.flake / 'flake.lock').read_bytes()
        self.calls.clear()
        # The mock build returns the already active system, just as a repeat
        # real build would. A differing candidate lock must not replace the
        # lock associated with that generation either.
        original_run = system.run
        def same_system_new_lock(args, **kwargs):
            result = original_run(args, **kwargs)
            if 'lock' in args:
                lock = Path(args[-1]) / 'flake.lock'
                data = json.loads(lock.read_text())
                data['nodes']['sleepy']['locked']['rev'] = 'b' * 40
                lock.write_text(json.dumps(data))
            return result
        with patch.object(system, 'run', side_effect=same_system_new_lock):
            self.assertEqual(system.system_action('update'), 0)
        self.assertEqual(self.profile.resolve(), self.new)
        self.assertEqual(receipt.read_bytes(), before_receipt)
        self.assertEqual((self.flake / 'flake.lock').read_bytes(), before_lock)
        self.assertFalse(any('--set' in args or args[-1] in ('switch', 'dry-activate')
                             for args in self.calls))
        system.system_action('rollback')
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'old lock')

    def test_rollback_preserves_lock_edited_since_update(self):
        system.system_action('update')
        (self.flake / 'flake.lock').write_text('subsequent admin edit')
        system.system_action('rollback')
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'subsequent admin edit')
        self.assertEqual(self.profile.resolve(), self.old)

    def test_rollback_preserves_deleted_source_lock(self):
        system.system_action('update')
        lock = self.flake / 'flake.lock'
        lock.unlink()
        self.assertEqual(system.system_action('rollback'), 0)
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertFalse(lock.exists())

    def test_rollback_when_host_directory_was_moved(self):
        system.system_action('update')
        moved = self.root / 'moved-host'
        self.flake.rename(moved)
        self.assertEqual(system.system_action('rollback'), 0)
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertFalse(self.flake.exists())
        self.assertEqual((moved / 'flake.lock').read_text(), NEW_LOCK)

    def test_persist_failure_restores_previous_system(self):
        with patch.object(system, 'atomic_write', side_effect=OSError('disk full')):
            with self.assertRaises(OSError):
                system.system_action('update')
        self.assertEqual(self.profile.resolve(), self.old)
        self.assertEqual((self.flake / 'flake.lock').read_text(), 'old lock')

    def test_untrusted_state_lock_rejected_before_backend(self):
        state = self.root / 'state'
        state.mkdir()
        (state / '.lock').symlink_to(self.config)
        with self.assertRaises(snug.SnugError):
            system.system_action('update')
        self.assertEqual(self.calls, [])

    def test_rejects_unowned_config_before_any_backend(self):
        underlying = system.os.lstat
        fields = list(underlying(self.config))
        fields[4] = 1000
        def unowned(path, *args, **kwargs):
            return os.stat_result(fields) if Path(path) == self.config else underlying(path, *args, **kwargs)
        with patch.object(system.os, 'lstat', side_effect=unowned):
            with self.assertRaises(snug.SnugError):
                system.system_action('update')
        self.assertEqual(self.calls, [])

    def test_unknown_input_cannot_silently_build_unchanged_system(self):
        config = json.loads(self.config.read_text())
        config['input'] = 'typo'
        self.config.write_text(json.dumps(config))
        with self.assertRaises(snug.SnugError):
            system.system_action('update')
        self.assertFalse(any('build' in args for args in self.calls))
        self.assertEqual(self.profile.resolve(), self.old)

    def test_nonroot_escalates_only_fixed_installed_entrypoint(self):
        with patch.object(system.os, 'geteuid', return_value=1000):
            self.assertEqual(system.system_action('update'), 0)
        self.assertEqual(self.calls, [['/run/wrappers/bin/sudo', '--',
                                      '/run/current-system/sw/bin/snug', 'update', '--system']])


if __name__ == '__main__':
    unittest.main()
