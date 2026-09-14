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

    def ask(self, *args, **kwargs):
        self.calls.append(args)
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

    def test_keyboard_choice_explains_us_fallback_and_switching(self):
        for keyboard in ('us', 'ru', 'de', 'cz'):
            with self.subTest(keyboard=keyboard):
                dialog = ScriptedDialog(['alice', 'ascii-password', 'ascii-password',
                                         'sleepy', 'en_US.UTF-8', keyboard, 'UTC', ''])
                result = tui.collect_request(dialog, DISK)
                self.assertEqual(result['keyboard'], keyboard)
                menu = next(call for call in dialog.calls if 'Installed keyboard layout' in call[2])
                self.assertIn('Alt+Shift', menu[2])
                self.assertIn('US', menu[2])
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
                   'sleepy', 'en_US.UTF-8', 'us', 'Europe/Prague', '', None, None]
        with patch.object(tui, 'list_disks', return_value=[DISK]), patch.object(tui, 'install') as install:
            tui.wizard(ScriptedDialog(answers))
            install.assert_not_called()

    def test_password_unicode_and_empty_optional_selection_reach_structured_backend(self):
        answers = ['install', '/dev/vda', 'alice', 'secret-☾', 'secret-☾',
                   'sleepy', 'en_US.UTF-8', 'us', 'Europe/Prague', '', '/dev/vda', 'exit']
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
                                 'sleepy', 'en_US.UTF-8', 'us', 'Europe/Prague', '', '/dev/vdb', None, None])
        with patch.object(tui, 'list_disks', return_value=[DISK]), patch.object(tui, 'install') as install:
            tui.wizard(dialog)
            install.assert_not_called()
        self.assertTrue(any('does not match' in message for _, message in dialog.messages))


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
                ('Language', '\r'), ('Installed keyboard layout', '\r'), ('Timezone', '\r'),
                ('Only what you need', '\r'), ('ERASE ALL DATA', '/dev/vda\r'),
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
