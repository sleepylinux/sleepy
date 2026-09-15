"""Recovery UI protocol tests; actual boot repair requires the separate VM gate."""
import subprocess
import unittest
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
        self.assertIn(('screen', 'Installed Sleepy'), events[:check])
        self.assertIn(('screen', 'Recover Sleepy boot'), events[:check])
        self.assertEqual(events.count(('text', '/dev/vda')), 1)
        self.assertEqual(events[-1], ('screen', 'Boot repair complete'))

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

    def test_fixed_guest_scripts_parse_and_reject_unknown_phase(self):
        for phase in ('damage', 'verify'):
            subprocess.run(['bash', '-n'], input=boot_recovery.fixture(phase), text=True, check=True)
        self.assertEqual(boot_recovery.fixture(None), '')
        with self.assertRaises(ValueError): boot_recovery.fixture('host')


if __name__ == '__main__': unittest.main()
