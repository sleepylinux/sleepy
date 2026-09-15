import importlib.util
import pathlib
import sys
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('tui', pathlib.Path(__file__).with_name('tui.py'))
tui = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tui)


class ScriptedDialog:
    def __init__(self, answers):
        self.answers = iter(answers)
        self.messages = []
        self.calls = []
        self.call_options = []

    def ask(self, *args, **kwargs):
        self.calls.append(args)
        self.call_options.append(kwargs)
        return next(self.answers)

    def message(self, title, message):
        self.messages.append((title, message))


DISK = dict(path='/dev/vda', identity='fingerprint', model='Disposable VM',
            size=21474836480, serial='test-123', eligible=True, reason='')


class WizardTests(unittest.TestCase):
    def test_reserved_username_is_rejected_at_account_step(self):
        # A service account must not reach the privileged installation operation.
        dialog = ScriptedDialog(['rtkit', None])
        self.assertIsNone(tui.collect_request(dialog, DISK))
        self.assertTrue(dialog.messages)

    def assert_field_retry(self, answers, retry_index, prompt, field, expected):
        dialog = ScriptedDialog(answers)
        original_ask = dialog.ask
        def ask(*args, **kwargs):
            if len(dialog.calls) == retry_index:
                self.assertTrue(args[2].startswith(prompt),
                                'invalid value advanced to another field')
            return original_ask(*args, **kwargs)
        with patch.object(dialog, 'ask', side_effect=ask):
            result = tui.collect_request(dialog, DISK)
        self.assertEqual(result[field], expected)
        self.assertEqual(len(dialog.messages), 1)

    def test_reserved_prefixes_retry_username_before_password_step(self):
        for invalid in ('rtkit', 'nixbld123', 'systemd-example'):
            with self.subTest(username=invalid):
                self.assert_field_retry(
                    [invalid, 'alice', 'ascii-password', 'ascii-password',
                     'sleepy', 'en_US.UTF-8', 'us', 'UTC', '', 'off'],
                    1, 'Username', 'username', 'alice')

    def test_trailing_hyphen_retries_hostname_before_region_step(self):
        for valid in ('a', 'sleepy-01'):
            with self.subTest(hostname=valid):
                self.assert_field_retry(
                    ['alice', 'ascii-password', 'ascii-password',
                     'sleepy-', valid, 'en_US.UTF-8', 'us', 'UTC', '', 'off'],
                    4, 'Computer name', 'hostname', valid)

    def test_keyboard_choice_explains_us_fallback_and_switching(self):
        for keyboard in ('us', 'ru', 'de', 'cz'):
            with self.subTest(keyboard=keyboard):
                dialog = ScriptedDialog(['alice', 'ascii-password', 'ascii-password',
                                         'sleepy', 'en_US.UTF-8', keyboard, 'UTC', '', 'off'])
                result = tui.collect_request(dialog, DISK)
                self.assertEqual(result['keyboard'], keyboard)
                menu = next(call for call in dialog.calls if 'Installed desktop keyboard layout' in call[2])
                self.assertIn('Alt+Shift', menu[2])
                self.assertIn('US', menu[2])
                self.assertIn('Recovery consoles always use US', menu[2])
                self.assertIn('US + Russian', menu)
                self.assertIn('US + German', menu)
                self.assertIn('US + Czech', menu)
                password = next(call for call in dialog.calls if 'Choose your login' in call[2])
                self.assertIn('US keyboard', password[2])

    def test_cancel_at_welcome_never_invokes_backend(self):
        with patch.object(tui, 'list_disks') as listing, patch.object(tui, 'install') as install:
            tui.wizard(ScriptedDialog([None]))
            listing.assert_not_called()
            install.assert_not_called()

    def test_cancel_erase_returns_without_install(self):
        answers = ['install', '/dev/vda', 'alice', 'secret-☾', 'secret-☾',
                   'sleepy', 'en_US.UTF-8', 'us', 'Europe/Prague', '', 'off', None, None]
        with patch.object(tui, 'list_disks', return_value=[DISK]), patch.object(tui, 'install') as install:
            tui.wizard(ScriptedDialog(answers))
            install.assert_not_called()

    def test_password_unicode_and_empty_optional_selection_reach_structured_backend(self):
        answers = ['install', '/dev/vda', 'alice', 'secret-☾', 'secret-☾',
                   'sleepy', 'en_US.UTF-8', 'us', 'Europe/Prague', '', 'off', '/dev/vda', 'exit']
        received = []
        def capture(_dialog, request):
            received.append(dict(request))
            return True
        with patch.object(tui, 'list_disks', return_value=[DISK]), patch.object(tui, 'install', side_effect=capture):
            tui.wizard(ScriptedDialog(answers))
        self.assertEqual(received[0]['password'], 'secret-☾')
        self.assertEqual(received[0]['confirm_erase'], '/dev/vda')
        self.assertEqual(received[0]['identity'], 'fingerprint')
        self.assertTrue(all(value is False for value in received[0]['options'].values()))

    def test_wrong_disk_confirmation_never_installs(self):
        dialog = ScriptedDialog(['install', '/dev/vda', 'alice', 'secret-☾', 'secret-☾',
                                 'sleepy', 'en_US.UTF-8', 'us', 'Europe/Prague', '', 'off', '/dev/vdb', None, None])
        with patch.object(tui, 'list_disks', return_value=[DISK]), patch.object(tui, 'install') as install:
            tui.wizard(dialog)
            install.assert_not_called()
        self.assertTrue(any('does not match' in message for _, message in dialog.messages))


class EncryptionTests(unittest.TestCase):
    def account(self):
        return ['alice','login-password','login-password','sleepy','en_US.UTF-8','us','UTC','']

    def test_default_off_is_separate_from_software_and_has_no_secret(self):
        dialog=ScriptedDialog(self.account()+['off'])
        result=tui.collect_request(dialog,DISK)
        self.assertIs(result.get('encryption'),False)
        self.assertNotIn('encryption_passphrase',result)
        menu=next(call for call in dialog.calls if 'Protect your files' in call[0])
        self.assertEqual(menu[1],'menu')
        self.assertEqual(dialog.call_options[dialog.calls.index(menu)]['default'], 'off')
        self.assertIn('US keyboard',menu[2])
        self.assertIn('every boot',menu[2])

    def test_encryption_validation_and_confirmation_retry_stay_hidden(self):
        phrase='twelve safe words'
        dialog=ScriptedDialog(self.account()+['on','short','nonascii-secret-é','x'*129,'control\tcharacter',phrase,'wrong confirmation',phrase])
        result=tui.collect_request(dialog,DISK)
        self.assertIs(result['encryption'],True)
        self.assertEqual(result['encryption_passphrase'],phrase)
        self.assertNotIn('encryption_passphrase_confirm',result)
        self.assertEqual(len(dialog.messages),5)
        encrypted_calls=[call for call in dialog.calls if call[1]=='passwordbox' and 'disk' in call[2].lower()]
        self.assertGreaterEqual(len(encrypted_calls),2)
        self.assertTrue(all(len(call)==3 for call in encrypted_calls))
        self.assertNotIn(phrase,repr(dialog.calls)+repr(dialog.messages))

    def test_back_from_confirmation_then_disable_forgets_passphrase(self):
        phrase='a distinct disk secret'
        dialog=ScriptedDialog(self.account()+['on',phrase,None,None,'off'])
        result=tui.collect_request(dialog,DISK)
        self.assertIs(result['encryption'],False)
        self.assertNotIn('encryption_passphrase',result)
        self.assertNotIn(phrase,repr(dialog.calls)+repr(dialog.messages))

    def test_cancel_erase_clears_all_secrets_and_never_installs(self):
        phrase='a distinct disk secret'
        request=dict(disk='/dev/vda',identity='fingerprint',username='alice',hostname='sleepy',
                     locale='en_US.UTF-8',timezone='UTC',keyboard='us',password='login-password',
                     encryption=True,encryption_passphrase=phrase,options={})
        dialog=ScriptedDialog(['install','/dev/vda',None,None])
        with patch.object(tui,'list_disks',return_value=[DISK]),patch.object(tui,'collect_request',return_value=request),patch.object(tui,'install') as install:
            tui.wizard(dialog)
        install.assert_not_called()
        self.assertNotIn('password',request)
        self.assertNotIn('encryption_passphrase',request)
        confirm=next(call for call in dialog.calls if 'ERASE ALL DATA' in call[2])
        self.assertIn('Encryption: on',confirm[2])
        self.assertNotIn(phrase,repr(dialog.calls)+repr(dialog.messages))

    def test_passphrase_boundaries_preserve_spaces(self):
        for phrase in (' ' + 'a' * 10 + ' ', 'b' * 128):
            with self.subTest(length=len(phrase)):
                dialog = ScriptedDialog(self.account() + ['on', phrase, phrase])
                result = tui.collect_request(dialog, DISK)
                self.assertEqual(result['encryption_passphrase'], phrase)
                self.assertEqual(dialog.messages, [])

    def test_back_to_software_drops_encryption_secret_before_reselect(self):
        phrase = 'a distinct disk secret'
        dialog = ScriptedDialog(self.account() + ['on', phrase, None, None, None, '', 'off'])
        result = tui.collect_request(dialog, DISK)
        self.assertIs(result['encryption'], False)
        self.assertNotIn('encryption_passphrase', result)

    def test_backend_spawn_failure_clears_secrets(self):
        request = {'password': 'login-password', 'encryption': True,
                   'encryption_passphrase': 'a distinct disk secret'}
        with patch.object(tui.subprocess, 'Popen', side_effect=OSError('cannot start')):
            with self.assertRaises(OSError):
                tui.install(ScriptedDialog([]), request)
        self.assertEqual(request, {'encryption': True})

    def test_successful_install_sends_secrets_only_to_backend_stdin(self):
        import io
        import json
        phrase = 'a distinct disk secret'
        request = {'password': 'login-password', 'encryption': True,
                   'encryption_passphrase': phrase}
        class Input(io.StringIO):
            def close(self):
                self.sent = self.getvalue()
                super().close()
        class Process:
            def __init__(self, output=''):
                self.stdin = Input()
                self.stdout = io.StringIO(output)
            def wait(self):
                return 0
            def poll(self):
                return 0
        backend = Process('{"stage":"complete","message":"Installed","progress":100}\n')
        gauge = Process()
        dialog = ScriptedDialog([])
        dialog.command = lambda title: ['dialog', title]
        dialog.env = {}
        with patch.object(tui.subprocess, 'Popen', side_effect=[backend, gauge]) as popen:
            self.assertTrue(tui.install(dialog, request))
        self.assertEqual(json.loads(backend.stdin.sent)['encryption_passphrase'], phrase)
        self.assertEqual(request, {'encryption': True})
        self.assertNotIn(phrase, repr(popen.call_args_list) + gauge.stdin.sent + repr(dialog.messages))

    def test_install_error_always_removes_secrets_after_stdin_transfer(self):
        import io
        phrase='a distinct disk secret';request={'password':'login-password','encryption':True,'encryption_passphrase':phrase}
        class Input(io.StringIO):
            def close(self):self.sent=self.getvalue();super().close()
        class Process:
            stdin=Input();stdout=io.StringIO('')
            def wait(self):return 1
            def poll(self):return 1
        process=Process();dialog=ScriptedDialog([])
        dialog.command=lambda title:['dialog',title];dialog.env={}
        with patch.object(tui.subprocess,'Popen',side_effect=[process,OSError('gauge failed')]) as popen:
            with self.assertRaises(OSError):tui.install(dialog,request)
        self.assertNotIn('password',request);self.assertNotIn('encryption_passphrase',request)
        self.assertIn(phrase,process.stdin.sent)
        self.assertNotIn(phrase,repr(popen.call_args_list)+repr(dialog.messages))


class TerminalTests(unittest.TestCase):
    def test_real_dialog_wizard_in_80x24_terminal(self):
        """Exercise real ncurses rendering and keys; replace only disk operations."""
        import errno
        import fcntl
        import os
        import pty
        import select
        import shutil
        import struct
        import subprocess
        import termios
        import time
        if not shutil.which('dialog'):
            self.skipTest('dialog executable is required for the terminal integration test')
        script = f'''
import sys
sys.path.insert(0, {str(pathlib.Path(__file__).parent)!r})
import tui
tui.list_disks = lambda: [{DISK!r}]
def install(dialog, request):
    assert request['password'] == 'test-password-123'
    assert request['confirm_erase'] == '/dev/vda'
    assert all(not enabled for enabled in request['options'].values())
    return True
tui.install = install
tui.main()
'''
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
        process = subprocess.Popen([sys.executable, '-c', script], stdin=slave, stdout=slave,
                                   stderr=slave, env=dict(os.environ, TERM='xterm', NCURSES_NO_UTF8_ACS='1'))
        os.close(slave)
        all_output = bytearray()
        def screen(expected):
            output = bytearray()
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        chunk = os.read(master, 65536)
                    except OSError as error:
                        if error.errno == errno.EIO:
                            break
                        raise
                    output.extend(chunk)
                    all_output.extend(chunk)
                elif expected.encode() in output:
                    return
            self.fail(f'No {expected!r} screen: {bytes(output)!r}')
        try:
            for expected, keys in [
                ('Welcome home', '\r'), ('Disposable VM', '\r'), ('Username', '\x15alice\r'),
                ('Choose your login password', 'test-password-123\r'),
                ('Type your password again', 'test-password-123\r'), ('Computer name', '\r'),
                ('Language', '\r'), ('Installed desktop keyboard layout', '\r'), ('Timezone', '\r'),
                ('Only what you need', '\r'), ('Protect your files', '\r'), ('ERASE ALL DATA', '/dev/vda\r'),
                ('Your new home is ready', '\x1b'),
            ]:
                screen(expected)
                os.write(master, keys.encode())
            self.assertEqual(process.wait(timeout=5), 0)
            self.assertNotIn(b'test-password-123', all_output)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)


if __name__ == '__main__':
    unittest.main()
