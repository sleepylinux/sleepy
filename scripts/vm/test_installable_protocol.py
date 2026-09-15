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
                             ('lock_fixture', 'advance_locked_vt', 'keyring_fixture', 'advance_daily_idle', 'daily_idle_fixture', 'update_fixture', 'daily_menu_focus_fixture', 'advance_daily_menu')], type_ignores=[]),
             str(SOURCE), 'exec'), NAMESPACE)


class LockedVTProtocol(unittest.TestCase):
    def test_waits_for_complete_guest_acknowledgements_and_does_not_repeat_keys(self):
        calls = []
        class QMP:
            def keys(self, *keys):
                calls.append(keys)
        qmp, sent, report = QMP(), set(), b''
        advance = NAMESPACE['advance_locked_vt']
        markers = (b'LOCK_SHELL_CRASH_WAKE_READY', b'LOCK_SWITCH_TO_CONSOLE', b'LOCK_CONSOLE_VT_READY',
                   b'LOCK_RETURNED_GRAPHICAL_VT_READY')
        for index, marker in enumerate(markers):
            advance(qmp, report + marker[:-1], sent)
            self.assertEqual(len(calls), index)
            report += marker + b'\n'
            advance(qmp, report, sent)
            advance(qmp, report, sent)
            self.assertEqual(len(calls), index + 1)
        self.assertEqual(calls, [('shift',), ('ctrl', 'alt', 'f2'), ('ctrl', 'alt', 'f1'), ('shift',)])

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
                           'LOCK_SHELL_CRASH_WAKE_READY', 'LOCK_SHELL_CRASH_INPUT_WAKE_OK',
                           'LOCK_SWITCH_TO_CONSOLE', 'LOCK_CONSOLE_VT_READY',
                           'LOCK_RETURNED_GRAPHICAL_VT_READY', 'LOCK_VT_ROUNDTRIP_READY',
                           'LOCK_READY_FOR_REAL_PASSWORD', 'REAL_PASSWORD_LOCK_UNLOCK_OK']
                positions = [script.index(marker) for marker in markers]
                self.assertEqual(positions, sorted(positions))
                locked = script[script.index('test "$locked" = true'):]
                self.assertLess(locked.index('--signal=KILL'), locked.index('hypr dispatch dpms off'))
                self.assertNotIn('hypr dispatch dpms on', locked)
                self.assertIn('length > 0 and all(.[]; .dpmsStatus == false)', locked)
                self.assertIn('length > 0 and all(.[]; .dpmsStatus == true)', locked)
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


class DevelopmentUpdateFixture(unittest.TestCase):
    def test_development_is_enabled_only_in_new_generation_and_validated_before_rollback(self):
        seed = NAMESPACE['update_fixture']('seed')
        updated = NAMESPACE['update_fixture']('rollback')
        previous = NAMESPACE['update_fixture']('verify')
        for fixture in (seed, updated, previous):
            subprocess.run(['bash', '-n'], input=fixture, text=True, check=True)
        self.assertIn('sleepy.features.development.enable = true;', seed)
        self.assertLess(seed.index('DEVELOPMENT_ABSENT_IN_BASE_GENERATION_OK'),
                        seed.index('sleepy.features.development.enable = true;'))
        self.assertIn('(builtins.getFlake "path:/etc/nixos").inputs.nixpkgs.outPath', updated)
        self.assertNotIn('github:NixOS/nixpkgs', updated)
        self.assertLess(updated.index('direnv allow'), updated.index('direnv exec'))
        self.assertLess(updated.index('DEVELOPMENT_PINNED_DIRENV_PROJECT_OK'),
                        updated.index('nix-env --profile'))
        self.assertIn('set -e; test "$SLEEPY_ALPHA_DEV_SHELL" = ready;', updated)
        self.assertIn('python3 -c "print(6 * 7)"', updated)
        self.assertIn('! command -v direnv', previous)
        self.assertIn('! command -v python3', previous)
        self.assertNotIn('development.enable = true', previous)



class DailyMenuProtocol(unittest.TestCase):
    def test_host_waits_for_seat_readback_and_never_repeats_escape(self):
        calls = []
        class QMP:
            def keys(self, *keys):
                calls.append(keys)
        class Machine:
            qmp = QMP()
            def wait_screen(self, fragments, name, timeout):
                self.assertions = (fragments, name, timeout)
                calls.append(('ocr',))
        machine, sent = Machine(), set()
        advance = NAMESPACE['advance_daily_menu']
        mapped, ready = b'DAILY_SYSTEM_MENU_MAPPED\n', b'DAILY_SYSTEM_MENU_READY\n'
        vt = b'DAILY_SYSTEM_MENU_VT_READY\n'
        advance(machine, ready, sent, 'test')
        advance(machine, mapped[:-1], sent, 'test')
        self.assertEqual(calls, [])
        advance(machine, mapped, sent, 'test')
        advance(machine, mapped + ready[:-1], sent, 'test')
        self.assertEqual(calls, [('ctrl', 'alt', 'f1')])
        advance(machine, mapped + vt, sent, 'test')
        advance(machine, mapped + vt, sent, 'test')
        self.assertEqual(calls, [('ctrl', 'alt', 'f1'), ('shift',)])
        advance(machine, mapped + vt + ready, sent, 'test')
        advance(machine, mapped + vt + ready, sent, 'test')
        self.assertEqual(calls, [('ctrl', 'alt', 'f1'), ('shift',), ('ocr',), ('esc',)])
        self.assertEqual(machine.assertions[2], 25)

    def test_guest_requires_active_vt_keyboard_and_exact_focused_address(self):
        # Execute the production shell predicate against successive observable
        # states; a successful focus dispatcher alone is not readiness.
        prefix = r'''
set -eu
system_menu_address=0xabc
cat() { if test "$1" = /sys/class/tty/tty0/active; then
  if test "$stage" = 1; then echo tty2; else echo tty1; fi
else command cat "$@"; fi; }
hypr() {
  case "$1" in
    devices)
      if test "$stage" = 2; then echo '{"keyboards":[]}';
      else echo '{"keyboards":[{"main":true}]}'; fi ;;
    dispatch) printf '%s\n' "$stage" >> "$TRACE" ;;
    activewindow)
      if test "$stage" = 3 || test "$NEVER_READY" = yes; then echo '{"address":"0xdef"}';
      else echo '{"address":"0xabc"}'; fi ;;
    *) return 2 ;;
  esac
}
wait_daily() {
  for stage in 1 2 3 4; do
    if "$@"; then test "$stage" = 4; return; fi
  done
  return 1
}
'''
        with tempfile.TemporaryDirectory() as directory:
            trace = Path(directory) / 'focus'
            env = dict(os.environ, TRACE=str(trace), NEVER_READY='no')
            script = prefix + NAMESPACE['daily_menu_focus_fixture']()
            result = subprocess.run(['bash'], input=script, text=True, capture_output=True,
                                    env=env, timeout=5)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout.splitlines(), ['DAILY_SYSTEM_MENU_VT_READY', 'DAILY_SYSTEM_MENU_READY'])
            self.assertEqual(trace.read_text().splitlines(), ['3', '4'])
            result = subprocess.run(['bash'], input=script, text=True, capture_output=True,
                                    env=env | {'NEVER_READY': 'yes'}, timeout=5)
            self.assertNotEqual(result.returncode, 0)
            self.assertNotIn('DAILY_SYSTEM_MENU_READY', result.stdout)


class SafetyDiagnostics(unittest.TestCase):
    def test_real_failure_preserves_bounded_redacted_diagnostics_and_marker(self):
        script = next(node.value.value for node in FUNCTIONS['safety_checks'].body
                      if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant)
                      and isinstance(node.value.value, str))
        prelude = script.split('backend = shutil.which', 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / 'backend.log'
            secret = 'private-password-must-not-appear'
            log.write_text('old data\n' * 10000 + 'preflight actual failure ' + secret)
            prelude = prelude.replace('"/var/log/sleepy-installer.log"', repr(str(log)))
            program = prelude + '\nprivate_values.append(' + repr(secret) + ')\n' + '''
for i in range(20):
    remember({'stage':'preflight', 'message':'event-' + str(i) + ' ' + private_values[0]})
remember({'stage':'error', 'message':'nix eval failed (exit 1)'})
raise RuntimeError(private_values[0])
'''
            result = subprocess.run(['python3', '-c', program], capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stderr, '')
        self.assertNotIn(secret, result.stdout)
        self.assertNotIn('Traceback', result.stdout)
        self.assertIn('nix eval failed (exit 1)', result.stdout)
        self.assertIn('preflight actual failure [REDACTED]', result.stdout)
        self.assertNotIn('event-0 ', result.stdout)
        self.assertLess(len(result.stdout), 20000)
        self.assertTrue(result.stdout.endswith('SLEEPY_SAFETY_FAILED\n'))

    def test_failure_marker_aborts_host_wait_without_waiting_for_shell_prompt(self):
        namespace = {'SHELL_PROMPT': 'shell-prompt'}
        exec(compile(ast.Module(body=[FUNCTIONS['serial_line']], type_ignores=[]), str(SOURCE), 'exec'), namespace)
        calls = []
        class Terminal:
            def sendline(self, line): calls.append(('send', line))
            def expect(self, patterns, timeout):
                calls.append(('expect', patterns, timeout))
                return 1
        with self.assertRaisesRegex(RuntimeError, 'installer-safety.log'):
            namespace['serial_line'](Terminal(), 'fixed-guest-command', 'SUCCESS',
                                     timeout=300, failure_marker='SLEEPY_SAFETY_FAILED')
        self.assertEqual(calls, [('send', 'fixed-guest-command'),
            ('expect', ['SUCCESS', 'SLEEPY_SAFETY_FAILED'], 300)])


if __name__ == '__main__':
    unittest.main()
