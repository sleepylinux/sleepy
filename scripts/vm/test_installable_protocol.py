"""Host/guest protocol regressions; these do not replace a real VM boot."""
import ast
from pathlib import Path
import subprocess
import unittest


SOURCE = Path(__file__).with_name('installable-alpha.py')
TREE = ast.parse(SOURCE.read_text())
FUNCTIONS = {node.name: node for node in TREE.body if isinstance(node, ast.FunctionDef)}
NAMESPACE = {}
exec(compile(ast.Module(body=[FUNCTIONS[name] for name in
                             ('lock_fixture', 'advance_locked_vt')], type_ignores=[]),
             str(SOURCE), 'exec'), NAMESPACE)


class LockedVTProtocol(unittest.TestCase):
    def test_waits_for_complete_guest_acknowledgements_and_does_not_repeat_keys(self):
        calls = []
        class QMP:
            def keys(self, *keys):
                calls.append(keys)
        qmp, sent, report = QMP(), set(), b''
        advance = NAMESPACE['advance_locked_vt']
        markers = (b'LOCK_SWITCH_TO_CONSOLE', b'LOCK_CONSOLE_VT_READY',
                   b'LOCK_RETURNED_GRAPHICAL_VT_READY')
        for index, marker in enumerate(markers):
            advance(qmp, report + marker[:-1], sent)
            self.assertEqual(len(calls), index)
            report += marker + b'\n'
            advance(qmp, report, sent)
            advance(qmp, report, sent)
            self.assertEqual(len(calls), index + 1)
        self.assertEqual(calls, [('ctrl', 'alt', 'f2'), ('ctrl', 'alt', 'f1'), ('shift',)])

    def test_later_acknowledgement_cannot_skip_prior_transition(self):
        class QMP:
            def keys(self, *_):
                raise AssertionError('transition before guest acknowledgement')
        NAMESPACE['advance_locked_vt'](QMP(), b'LOCK_CONSOLE_VT_READY', set())

    def test_generated_fixtures_keep_locked_roundtrip_before_native_auth(self):
        for keyboard in ('us', 'ru', 'de', 'cz'):
            with self.subTest(keyboard=keyboard):
                script = NAMESPACE['lock_fixture'](keyboard)
                subprocess.run(['bash', '-n'], input=script, text=True, check=True)
                self.assertNotIn('__GROUP__', script)
                markers = ['IDLE_LOCK_NATIVE_UNLOCK_OK', 'KEYBOARD_LAYOUT_SELECTED_OK',
                           'LOCK_SWITCH_TO_CONSOLE', 'LOCK_CONSOLE_VT_READY',
                           'LOCK_RETURNED_GRAPHICAL_VT_READY', 'LOCK_VT_ROUNDTRIP_READY',
                           'LOCK_READY_FOR_REAL_PASSWORD', 'REAL_PASSWORD_LOCK_UNLOCK_OK']
                positions = [script.index(marker) for marker in markers]
                self.assertEqual(positions, sorted(positions))
                locked = script[script.index('test "$locked" = true'):]
                self.assertIn('= tty2;', locked)
                self.assertIn('= tty1;', locked)
                self.assertIn('test "$(locker_state)" = locked', locked)
                expected_group = '0' if keyboard == 'us' else '1'
                self.assertEqual(script.count('hypr switchxkblayout all ' + expected_group),
                                 3 if keyboard == 'us' else 2)
                self.assertIn("== [\"English (US)\"]", locked)


if __name__ == '__main__':
    unittest.main()
