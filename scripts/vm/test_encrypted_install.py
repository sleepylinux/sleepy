"""Behavior gates over observed VM frames; no real encrypted VM claim."""
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch
import os
import stat
import subprocess
import tempfile
import unittest

import encrypted_install as gate

PROMPT = 'Please enter passphrase for disk luks-1234:'
FAILED = 'Failed to activate with specified passphrase. (Passphrase incorrect?)'


class EncryptionGateTests(unittest.TestCase):
    def machine(self, frames=()):
        return SimpleNamespace(encrypt_install=True, disk_passphrase='private-fixture-value',
                               encryption_completed=[], qmp=Mock(), process=Mock(poll=lambda: None),
                               screen=Mock(side_effect=frames), wait_screen=Mock())

    def test_default_off_does_not_enter_or_create_a_disk_secret(self):
        machine = self.machine(); machine.encrypt_install = False
        gate.select_protection(machine)
        machine.qmp.keys.assert_called_once_with('ret')
        machine.qmp.text.assert_not_called()
        machine.wait_screen.assert_called_once_with('Protect your files', 'installer-protection')
        gate.unlock(machine, 'boot'); machine.screen.assert_not_called()

    def test_encrypted_selection_enters_hidden_secret_twice(self):
        machine = self.machine(['selected'])
        gate.select_protection(machine)
        self.assertEqual([c.args for c in machine.qmp.keys.call_args_list], [('down',), ('ret',)])
        self.assertEqual([c.args for c in machine.qmp.text.call_args_list],
                         [('private-fixture-value\n',), ('private-fixture-value\n',)])
        self.assertTrue(all('Your input stays hidden' in c.args[0]
                            for c in machine.wait_screen.call_args_list[1:]))

    def test_wrong_secret_requires_explicit_rejection_and_new_retry_prompt(self):
        machine = self.machine([PROMPT, PROMPT + FAILED, PROMPT + FAILED,
                                PROMPT + FAILED + PROMPT])
        with patch.object(gate.time, 'sleep') as sleep:
            gate.unlock(machine, 'installed')
        self.assertEqual(sleep.call_count, 1, 'old prompt before failure cannot unlock')
        self.assertEqual([c.args for c in machine.qmp.text.call_args_list],
                         [('intentionally-wrong-disk-passphrase\n',), ('private-fixture-value\n',)])
        self.assertEqual(machine.encryption_completed, ['wrong-disk-passphrase-rejected'])
        machine.screen = Mock(return_value=PROMPT)
        machine.qmp.reset_mock()
        gate.unlock(machine, 'offline-reboot')
        machine.qmp.text.assert_called_once_with('private-fixture-value\n')
        self.assertEqual(machine.encryption_completed, ['wrong-disk-passphrase-rejected'])

    def test_greeter_without_wrong_password_rejection_fails_closed(self):
        machine = self.machine([PROMPT, 'Welcome back'])
        with self.assertRaisesRegex(RuntimeError, 'without the required unlock'):
            gate.unlock(machine, 'installed')
        machine.qmp.text.assert_called_once_with('intentionally-wrong-disk-passphrase\n')
        self.assertEqual(machine.encryption_completed, [])

    def test_missing_prompt_never_receives_secret_and_deadline_is_bounded(self):
        machine = self.machine(['booting'])
        with patch.object(gate.time, 'monotonic', side_effect=[0, 0, 181]), patch.object(gate.time, 'sleep'):
            with self.assertRaisesRegex(RuntimeError, 'prompt or explicit rejection missing'):
                gate.unlock(machine, 'installed')
        machine.qmp.text.assert_not_called()

    def test_credential_is_separate_private_and_exclusive(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            value = gate.credential(root)
            path = root / 'test-disk-credential'
            self.assertEqual(path.read_text(), value + '\n')
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertTrue(12 <= len(value) <= 128)
            with self.assertRaises(FileExistsError): gate.credential(root)
            self.assertEqual(path.read_text(), value + '\n')

    def test_guest_audit_shell_and_embedded_python_are_valid(self):
        script = gate.fixture()
        subprocess.run(['bash', '-n'], input=script, text=True, check=True)
        body = script.split("<<'ENCRYPTED_ROOT'\n", 1)[1].split('\nENCRYPTED_ROOT', 1)[0]
        compile(body, '<encrypted-root-audit>', 'exec')


if __name__ == '__main__':
    unittest.main()
