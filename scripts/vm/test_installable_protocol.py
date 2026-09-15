"""Host/guest protocol regressions; these do not replace a real VM boot."""
import ast
from pathlib import Path
import subprocess
import tempfile
import os
import unittest


SOURCE = Path(__file__).with_name('installable-alpha.py')
TREE = ast.parse(SOURCE.read_text())
FUNCTIONS = {node.name: node for node in TREE.body if isinstance(node, ast.FunctionDef)}
NAMESPACE = {}
exec(compile(ast.Module(body=[FUNCTIONS[name] for name in
                             ('lock_fixture', 'advance_locked_vt', 'keyring_fixture', 'advance_daily_idle', 'daily_idle_fixture')], type_ignores=[]),
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


class KeyringFixture(unittest.TestCase):
    def test_real_shell_protocol_requires_unlocked_collection_and_preserves_value(self):
        prelude = r"""
set -euo pipefail
timeout() { shift; "$@"; }
nix-store() { printf '/nix/store/fixture-libsecret-1\n'; }
test() {
  if [[ "${1-}" = -x && "${2-}" = /nix/store/fixture-libsecret-1/bin/secret-tool ]]; then return 0; fi
  builtin test "$@"
}
uenv() {
  shift 2
  case "$1" in
    busctl) printf '%s\n' "$LOCK_STATE" ;;
    systemctl) printf '%s\n' "$LOAD_STATE" ;;
    /nix/store/fixture-libsecret-1/bin/secret-tool)
      case "$2" in
        store) cat > "$STORE" ;;
        lookup) cat "$STORE" ;;
        *) return 2 ;;
      esac ;;
    *) return 2 ;;
  esac
}
"""
        with tempfile.TemporaryDirectory() as directory:
            store = Path(directory) / 'keyring'
            env = dict(os.environ, STORE=str(store), LOCK_STATE='b false', LOAD_STATE='not-found')
            def run(reboot):
                fixture = NAMESPACE['keyring_fixture'](reboot).replace(
                    '/tmp/sleepy-alpha-system-closure', directory + '/closure')
                return subprocess.run(['bash'], input=prelude + fixture, text=True,
                                      capture_output=True, env=env)
            first = run(False)
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertEqual(first.stdout.strip(), 'DAILY_KEYRING_STORE_LOOKUP_OK')
            prior = store.stat().st_mtime_ns
            reboot = run(True)
            self.assertEqual(reboot.returncode, 0, reboot.stderr)
            self.assertEqual(reboot.stdout.strip(), 'DAILY_KEYRING_PERSISTED_UNLOCKED_OK')
            self.assertEqual(store.stat().st_mtime_ns, prior)
            store.write_text('wrong value')
            self.assertNotEqual(run(True).returncode, 0)
            env['LOCK_STATE'] = 'b true'
            self.assertNotEqual(run(False).returncode, 0)
            self.assertEqual(store.read_text(), 'wrong value')
            env.update(LOCK_STATE='b false', LOAD_STATE='bad-setting')
            self.assertNotEqual(run(False).returncode, 0)
            self.assertEqual(store.read_text(), 'wrong value')

    def test_reboot_reads_existing_value_without_rewriting_it(self):
        first = NAMESPACE['keyring_fixture'](False)
        reboot = NAMESPACE['keyring_fixture'](True)
        self.assertIn(' store --label=Sleepy-VM-regression', first)
        self.assertNotIn(' store ', reboot)
        for fixture in (first, reboot):
            subprocess.run(['bash', '-n'], input=fixture, text=True, check=True)
            self.assertIn(' lookup sleepy-alpha regression', fixture)
            self.assertLess(fixture.index("= 'b false'"), fixture.index(' lookup '))
            self.assertIn('test "$keyring_load" != bad-setting', fixture)
            self.assertIn('timeout 10 "$secret_tool" lookup', fixture)
            self.assertNotIn('echo "$keyring_value"', fixture)
        self.assertIn('DAILY_KEYRING_STORE_LOOKUP_OK', first)
        self.assertIn('DAILY_KEYRING_PERSISTED_UNLOCKED_OK', reboot)


class IdleSamplingProtocol(unittest.TestCase):
    def test_complete_acknowledgements_switch_to_desktop_then_back_only_once(self):
        calls = []
        class QMP:
            def keys(self, *keys):
                calls.append(keys)
        qmp, sent = QMP(), set()
        advance = NAMESPACE['advance_daily_idle']
        advance(qmp, b'DAILY_IDLE_SHELL_STABLE_OK\n', sent)
        self.assertEqual(calls, [])
        advance(qmp, b'DAILY_IDLE_SAMPLE_READY', sent)
        self.assertEqual(calls, [])
        ready = b'DAILY_IDLE_SAMPLE_READY\n'
        advance(qmp, ready, sent)
        advance(qmp, ready, sent)
        self.assertEqual(calls, [('ctrl', 'alt', 'f1'), ('shift',)])
        advance(qmp, ready + b'DAILY_IDLE_SHELL_STABLE_OK', sent)
        self.assertEqual(len(calls), 2)
        advance(qmp, ready + b'DAILY_IDLE_SHELL_STABLE_OK\n', sent)
        advance(qmp, ready + b'DAILY_IDLE_SHELL_STABLE_OK\n', sent)
        self.assertEqual(calls[-1], ('ctrl', 'alt', 'f2'))
        self.assertEqual(len(calls), 3)

    def test_actual_dispatch_keeps_coalesced_unlock_and_idle_markers_on_desktop(self):
        # Execute the actual host dispatch statements, not a copy of their order.
        loop = next(node for node in ast.walk(FUNCTIONS['guest_report'])
                    if isinstance(node, ast.While) and 'SLEEPY_REPORT_COMPLETE' in ast.unparse(node.test))
        first_if = next(i for i, node in enumerate(loop.body) if isinstance(node, ast.If)
                        and 'LOCK_RETURN_TO_DESKTOP' in ast.unparse(node.test))
        dispatch = ast.Module(body=loop.body[first_if:], type_ignores=[])
        calls = []
        class QMP:
            def keys(self, *keys): calls.append(keys)
        class Machine:
            qmp = QMP()
            daily_usability = True
            def screen(self, name): pass
        namespace = dict(NAMESPACE, machine=Machine(), report=(
            b'REAL_PASSWORD_LOCK_UNLOCK_OK\nDAILY_IDLE_SAMPLE_READY\n'),
            daily_sent=set(), lock_desktop_shown=False, lock_graphical_woken=False,
            idle_lock_input_sent=False, lock_input_sent=False,
            lock_returned_to_console=False, stage='fixture')
        exec(compile(dispatch, str(SOURCE), 'exec'), namespace)
        self.assertEqual(calls, [('ctrl', 'alt', 'f2'), ('ctrl', 'alt', 'f1'), ('shift',)])

    def test_idle_fixture_shell_and_embedded_python_parse(self):
        script = NAMESPACE['daily_idle_fixture']()
        subprocess.run(['bash', '-n'], input=script, text=True, check=True)
        python = script.split("<<'IDLE_PY'\n", 1)[1].split('\nIDLE_PY', 1)[0]
        compile(python, '<guest-idle-sampler>', 'exec')


if __name__ == '__main__':
    unittest.main()
