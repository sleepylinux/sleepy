#!/usr/bin/env python3
"""Fresh shell configuration publication and preservation checks."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'modules/home/session/ensure-shell-config.py'
TEMPLATE = HELPER.with_name('default-shell.json')
spec = importlib.util.spec_from_file_location('shell_defaults', HELPER)
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class ShellDefaultsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.directory = self.root / 'config/sleepy'
        self.directory.mkdir(parents=True)
        self.target = self.directory / 'shell.json'

    def test_fresh_config_uses_suspend_and_preserves_other_actions(self):
        self.assertTrue(helper.initialize(self.directory, TEMPLATE))
        config = json.loads(self.target.read_text())
        self.assertEqual(config['general']['idle']['timeouts'], [
            {'timeout': 180, 'idleAction': 'lock'},
            {'timeout': 300, 'idleAction': 'dpms off', 'returnAction': 'dpms on'},
            {'timeout': 600, 'idleAction': ['suspend']}])
        actions = config['launcher']['actions']
        self.assertEqual([a['name'] for a in actions], [
            'Calculator', 'Scheme', 'Wallpaper', 'Variant', 'Random', 'Light',
            'Dark', 'Shutdown', 'Reboot', 'Logout', 'Lock', 'Sleep', 'Settings'])
        self.assertEqual(next(a for a in actions if a['name'] == 'Sleep')['command'], ['suspend'])
        self.assertEqual(next(a for a in actions if a['name'] == 'Lock')['command'], ['loginctl', 'lock-session'])
        self.assertEqual({a['name'] for a in actions if a.get('dangerous')}, {'Shutdown', 'Reboot', 'Logout'})
        self.assertNotIn('suspendThenHibernate', self.target.read_text())
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(list(self.directory.iterdir()), [self.target])

    def test_existing_custom_config_bytes_and_mode_unchanged(self):
        content = b'{"custom": true, "idleAction": ["suspendThenHibernate"]}\n'
        self.target.write_bytes(content)
        self.target.chmod(0o640)
        before = self.target.stat()
        self.assertFalse(helper.initialize(self.directory, TEMPLATE))
        self.assertEqual(self.target.read_bytes(), content)
        self.assertEqual(self.target.stat(), before)

    def test_existing_regular_and_dangling_symlinks_preserved(self):
        outside = self.root / 'custom.json'
        for exists in (False, True):
            with self.subTest(exists=exists):
                if exists:
                    outside.write_bytes(b'custom bytes')
                self.target.symlink_to(outside)
                self.assertFalse(helper.initialize(self.directory, TEMPLATE))
                self.assertEqual(os.readlink(self.target), str(outside))
                if exists:
                    self.assertEqual(outside.read_bytes(), b'custom bytes')
                else:
                    self.assertFalse(outside.exists())
                self.target.unlink()

    def test_symlink_parent_rejected_without_writing_target(self):
        self.directory.rmdir()
        outside = self.root / 'outside'
        outside.mkdir()
        self.directory.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(OSError):
            helper.initialize(self.directory, TEMPLATE)
        self.assertEqual(list(outside.iterdir()), [])

    def test_regular_file_parent_rejected(self):
        self.directory.rmdir()
        self.directory.write_bytes(b'keep')
        with self.assertRaises(OSError):
            helper.initialize(self.directory, TEMPLATE)
        self.assertEqual(self.directory.read_bytes(), b'keep')

    def test_new_parent_is_private(self):
        self.directory.rmdir()
        self.assertTrue(helper.initialize(self.directory, TEMPLATE))
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)

    def test_invalid_template_leaves_no_partial_config(self):
        invalid = self.root / 'invalid.json'
        invalid.write_text('{invalid')
        with self.assertRaises(ValueError):
            helper.initialize(self.directory, invalid)
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_concurrent_initializers_publish_one_complete_file(self):
        processes = [subprocess.Popen([sys.executable, str(HELPER), str(self.directory), str(TEMPLATE)])
                     for _ in range(8)]
        self.assertEqual([process.wait() for process in processes], [0] * 8)
        self.assertEqual(self.target.read_bytes(), TEMPLATE.read_bytes())
        self.assertEqual(list(self.directory.iterdir()), [self.target])


if __name__ == '__main__':
    unittest.main()
