"""Recovery UI protocol tests; actual boot repair requires the separate VM gate."""
import subprocess
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch
import os
import stat
import sys
import boot_recovery


class RecoveryProtocol(unittest.TestCase):
    def test_inspection_cancel_is_verified_before_destructive_confirmation(self):
        events = []
        class Machine:
            def __init__(self): self.qmp = self
            def wait_screen(self, text, name, **kwargs): events.append(('screen', text))
            def keys(self, *keys): events.append(('keys', keys))
            def text(self, text): events.append(('text', text))
        boot_recovery.recovery_tui(Machine(), lambda: events.append(('cancel-checked',)))
        check = events.index(('cancel-checked',))
        confirm = events.index(('text', '/dev/vda'))
        self.assertLess(check, confirm)
        self.assertIn(('screen', ['Installed Sleepy', 'Current generation:', 'Retained generations:']), events[:check])
        self.assertIn(('screen', 'Recover Sleepy boot'), events[:check])
        self.assertEqual(events.count(('text', '/dev/vda')), 1)
        self.assertEqual(events[-1], ('screen', 'Boot repair complete'))

    def test_inspection_wait_cannot_match_the_disk_selection_prompt(self):
        waits = []
        class Machine:
            def __init__(self): self.qmp = self
            def wait_screen(self, fragments, name, **kwargs): waits.append((fragments, name))
            def keys(self, *args): pass
            def text(self, value): pass
        boot_recovery.recovery_tui(Machine(), lambda: None)
        disk = 'Recover Sleepy boot. Inspect an installed Sleepy disk without changing it.'
        inspection = 'Installed Sleepy. Current generation: 1. Retained generations: 1 (1 total)'
        inspected = 0
        for fragments, name in waits:
            if name in ('recovery-inspection', 'recovery-inspection-again'):
                parts = [fragments] if isinstance(fragments, str) else fragments
                self.assertFalse(all(part.lower() in disk.lower() for part in parts))
                self.assertTrue(all(part.lower() in inspection.lower() for part in parts))
                inspected += 1
        self.assertEqual(inspected, 2)

    def test_failed_cancel_integrity_check_never_confirms_repair(self):
        texts = []
        class Machine:
            def __init__(self): self.qmp = self
            def wait_screen(self, *args, **kwargs): pass
            def keys(self, *args): pass
            def text(self, value): texts.append(value)
        def reject(): raise RuntimeError('ESP changed during inspect/cancel')
        with self.assertRaisesRegex(RuntimeError, 'ESP changed'):
            boot_recovery.recovery_tui(Machine(), reject)
        self.assertEqual(texts, [])

    def test_encrypted_wrong_passphrase_and_cancel_precede_repair(self):
        events = []
        class Machine:
            encrypt_install = True
            disk_passphrase = 'private-fixture-secret'
            encryption_completed = []
            def __init__(self): self.qmp = self
            def wait_screen(self, text, name, **kwargs): events.append(('screen', text, name))
            def keys(self, *keys): events.append(('keys', keys))
            def text(self, text): events.append(('text', text))
        machine = Machine()
        boot_recovery.recovery_tui(machine, lambda: events.append(('integrity-checked',)))
        writes = [event[1] for event in events if event[0] == 'text']
        self.assertEqual(writes, ['intentionally-wrong-disk-passphrase\n',
            'private-fixture-secret\n', 'private-fixture-secret\n', '/dev/vda'])
        checks = [i for i, event in enumerate(events) if event[0] == 'integrity-checked']
        self.assertEqual(len(checks), 2)
        self.assertLess(checks[0], events.index(('text', 'private-fixture-secret\n')))
        self.assertLess(checks[1], events.index(('text', '/dev/vda')))
        rejected = next(i for i,e in enumerate(events) if e[0] == 'screen' and e[2] == 'recovery-wrong-passphrase-rejected')
        self.assertLess(rejected, checks[0])
        self.assertEqual(events[rejected][1], ['Recovery needs attention', 'cryptsetup failed'])
        self.assertEqual(machine.encryption_completed, ['recovery-wrong-passphrase-preserved-partitions'])
        self.assertEqual(events[-1][2], 'recovery-complete')

    def test_encrypted_rejection_without_integrity_proof_never_enters_correct_secret(self):
        writes = []
        class Machine:
            encrypt_install = True
            disk_passphrase = 'private-fixture-secret'
            encryption_completed = []
            def __init__(self): self.qmp = self
            def wait_screen(self, *args, **kwargs): pass
            def keys(self, *args): pass
            def text(self, text): writes.append(text)
        def reject(): raise RuntimeError('Encrypted partition changed')
        with self.assertRaisesRegex(RuntimeError, 'Encrypted partition changed'):
            boot_recovery.recovery_tui(Machine(), reject)
        self.assertEqual(writes, ['intentionally-wrong-disk-passphrase\n'])

    def test_actual_encrypted_root_guard_rejects_another_disk_or_non_luks(self):
        script = boot_recovery.fixture('damage', encrypted=True)
        subprocess.run(['bash', '-n'], input=script, text=True, check=True)
        body = script.split("<<'RECOVERY_ROOT_DEVICE'\n",1)[1].split('\nRECOVERY_ROOT_DEVICE',1)[0]
        for name, dm, accepted in [('vda2', 'CRYPT-LUKS2-test', True),
                ('sda2', 'CRYPT-LUKS2-test', False), ('vda2', 'LVM-other', False)]:
            with self.subTest(name=name, dm=dm), patch.object(sys, 'argv', ['audit', '/dev/dm-0']), \
                    patch.object(os, 'stat', return_value=SimpleNamespace(st_mode=stat.S_IFBLK, st_rdev=os.makedev(253,0))), \
                    patch.object(Path, 'read_text', return_value=dm), \
                    patch.object(Path, 'iterdir', return_value=iter([Path('/sys/block/'+name)])):
                if accepted: exec(compile(body, '<recovery-root-guard>', 'exec'), {})
                else:
                    with self.assertRaises(AssertionError): exec(compile(body, '<recovery-root-guard>', 'exec'), {})
        subprocess.run(['bash', '-n'], input=boot_recovery.fixture('verify', encrypted=True), text=True, check=True)

    def test_fixed_guest_scripts_parse_and_reject_unknown_phase(self):
        for phase in ('damage', 'verify'):
            subprocess.run(['bash', '-n'], input=boot_recovery.fixture(phase), text=True, check=True)
        self.assertEqual(boot_recovery.fixture(None), '')
        with self.assertRaises(ValueError): boot_recovery.fixture('host')


if __name__ == '__main__': unittest.main()
