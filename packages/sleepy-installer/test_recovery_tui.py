import subprocess
import unittest
from unittest.mock import Mock, patch

import recovery_tui


class Dialog:
    def __init__(self, answers): self.answers = iter(answers); self.prompts = []; self.messages = []; self.calls = []
    def ask(self, title, kind, text, *items, **options):
        self.calls.append((title, kind, text, items, options))
        self.prompts.append((title, text, options))
        try: return next(self.answers)
        except StopIteration: raise AssertionError('Unexpected dialog: ' + title)
    def message(self, title, text): self.messages.append((title, text))


class RecoveryTuiTests(unittest.TestCase):
    def setUp(self):
        self.disk = dict(path='/dev/vda', identity='a' * 64, size=32 * 1024**3, model='Test disk', serial='test', eligible=True)
        self.metadata = dict(current=1, installation='b' * 64, generations=[dict(generation=1)])

    def test_inspect_then_back_never_repairs(self):
        dialog = Dialog(['/dev/vda', 'back', 'back'])
        with patch.object(recovery_tui, 'list_disks', return_value=[self.disk]), patch.object(recovery_tui, 'inspect', return_value=self.metadata) as inspect, patch.object(recovery_tui, 'restore') as restore:
            recovery_tui.wizard(dialog)
        inspect.assert_called_once_with(dict(disk='/dev/vda', identity='a' * 64))
        restore.assert_not_called()
        self.assertEqual(dialog.prompts[1][2]['default'], 'back')

    def test_explicit_disk_confirmation_is_required_and_explains_trusted_code(self):
        dialog = Dialog(['/dev/vda', 'restore', '/dev/vdb', 'back'])
        with patch.object(recovery_tui, 'list_disks', return_value=[self.disk]), patch.object(recovery_tui, 'inspect', return_value=self.metadata), patch.object(recovery_tui, 'restore') as restore:
            recovery_tui.wizard(dialog)
        restore.assert_not_called()
        self.assertIn('installed OS as root', dialog.prompts[2][1])

    def test_confirmed_restore_uses_only_inspected_snapshot(self):
        dialog = Dialog(['/dev/vda', 'restore', '/dev/vda'])
        with patch.object(recovery_tui, 'list_disks', return_value=[self.disk]), patch.object(recovery_tui, 'inspect', return_value=self.metadata), patch.object(recovery_tui, 'restore', return_value=True) as restore:
            recovery_tui.wizard(dialog)
        restore.assert_called_once_with(dialog, dict(disk='/dev/vda', identity='a' * 64, installation='b' * 64, confirm_restore='/dev/vda'))

    def encrypted_run(self, answers, *, error=None, restore_result=True):
        dialog = Dialog(['/dev/vda'] + answers)
        snapshots, requests = [], []
        def inspect(request):
            requests.append(request)
            snapshots.append(dict(request))
            if len(snapshots) == 1:
                return dict(encrypted=True, locked=True, disk='/dev/vda', identity='a' * 64)
            if error:
                raise error
            return dict(self.metadata, encrypted=True, locked=False)
        restored = []
        def restore(_dialog, request):
            restored.append(dict(request))
            return restore_result
        with patch.object(recovery_tui, 'list_disks', return_value=[self.disk]), patch.object(recovery_tui, 'inspect', side_effect=inspect), patch.object(recovery_tui, 'restore', side_effect=restore):
            recovery_tui.wizard(dialog)
        self.assertTrue(all('encryption_passphrase' not in request for request in requests))
        return dialog, snapshots, restored

    def test_encrypted_inspection_restore_hidden_secret_and_cleanup(self):
        phrase = 'a safe disk passphrase'
        dialog, inspected, restored = self.encrypted_run([phrase, 'restore', '/dev/vda'])
        self.assertEqual(inspected[1]['encryption_passphrase'], phrase)
        self.assertEqual(restored[0]['encryption_passphrase'], phrase)
        self.assertEqual(restored[0]['installation'], self.metadata['installation'])
        prompt = next(call for call in dialog.calls if call[1] == 'passwordbox')
        self.assertEqual(prompt[3], ())
        self.assertIn('US keyboard', prompt[2])
        self.assertNotIn(phrase, repr(dialog.calls) + repr(dialog.messages))

    def test_passphrase_validation_retries_before_backend(self):
        dialog, inspected, restored = self.encrypted_run(['short', 'nonascii-secret-é', 'a safe disk passphrase', 'back', 'back'])
        self.assertEqual(len(inspected), 2)
        self.assertEqual(len(dialog.messages), 2)
        self.assertEqual(restored, [])

    def test_cancel_passphrase_does_not_unlock_or_restore(self):
        _, inspected, restored = self.encrypted_run([None, 'back'])
        self.assertEqual(len(inspected), 1)
        self.assertEqual(restored, [])

    def test_back_and_confirmation_cancel_or_mismatch_clear_secret(self):
        for tail in (['back', 'back'], ['restore', None, 'back'], ['restore', '/dev/vdb', 'back']):
            with self.subTest(tail=tail):
                _, _, restored = self.encrypted_run(['a safe disk passphrase'] + tail)
                self.assertEqual(restored, [])

    def test_failed_unlock_clears_secret_and_reports_error(self):
        phrase = 'a safe disk passphrase'
        dialog, _, restored = self.encrypted_run([phrase, 'back'], error=RuntimeError('Cannot unlock disk'))
        self.assertEqual(restored, [])
        self.assertIn('Cannot unlock disk', dialog.messages[0][1])
        self.assertNotIn(phrase, repr(dialog.messages))

    def test_interrupted_unlock_clears_secret(self):
        requests = []
        def inspect(request):
            requests.append(request)
            if len(requests) == 1:
                return dict(encrypted=True, locked=True)
            raise KeyboardInterrupt()
        with patch.object(recovery_tui, 'list_disks', return_value=[self.disk]), patch.object(recovery_tui, 'inspect', side_effect=inspect):
            with self.assertRaises(KeyboardInterrupt):
                recovery_tui.wizard(Dialog(['/dev/vda', 'a safe disk passphrase']))
        self.assertTrue(all('encryption_passphrase' not in request for request in requests))

    def test_restore_transport_clears_secret_on_success_and_errors(self):
        import io
        import json
        phrase = 'a safe disk passphrase'
        class Input(io.StringIO):
            def close(self):
                self.sent = self.getvalue()
                super().close()
        for scenario in ('success', 'spawn-error', 'gauge-error', 'invalid-event'):
            with self.subTest(scenario=scenario):
                request = dict(encryption_passphrase=phrase, disk='/dev/vda')
                process = Mock(stdin=Input(), stdout=io.StringIO(
                    'invalid\n' if scenario == 'invalid-event' else
                    '{"stage":"complete","message":"Restored","progress":100}\n'))
                process.poll.return_value = 0
                process.wait.return_value = 0
                gauge = Mock(stdin=Input())
                gauge.poll.return_value = 0
                dialog = Dialog([])
                dialog.command = lambda title: ['dialog', title]
                dialog.env = {}
                sequence = [OSError('cannot start')] if scenario == 'spawn-error' else [process,
                    OSError('gauge failed') if scenario == 'gauge-error' else gauge]
                with patch.object(recovery_tui.subprocess, 'Popen', side_effect=sequence) as popen:
                    if scenario == 'success':
                        self.assertTrue(recovery_tui.restore(dialog, request))
                    else:
                        with self.assertRaises((OSError, ValueError)):
                            recovery_tui.restore(dialog, request)
                self.assertNotIn('encryption_passphrase', request)
                if scenario != 'spawn-error':
                    self.assertEqual(json.loads(process.stdin.sent)['encryption_passphrase'], phrase)
                self.assertNotIn(phrase, repr(popen.call_args_list) + repr(dialog.messages))

    def test_inspect_transport_uses_stdin_not_command_arguments(self):
        import json
        phrase = 'a safe disk passphrase'
        request = dict(disk='/dev/vda', identity='a' * 64, encryption_passphrase=phrase)
        process = Mock(returncode=0)
        process.communicate.return_value = (json.dumps(self.metadata), None)
        process.poll.return_value = 0
        with patch.object(recovery_tui.subprocess, 'Popen', return_value=process) as popen:
            self.assertEqual(recovery_tui.inspect(request), self.metadata)
        self.assertEqual(json.loads(process.communicate.call_args.args[0]), request)
        self.assertNotIn(phrase, repr(popen.call_args_list))

    def test_child_cleanup_grace_exceeds_backend_grace_then_reaps(self):
        process = Mock(pid=1234)
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired('sudo', 15), 0]
        with patch.object(recovery_tui.os, 'killpg') as kill:
            recovery_tui.stop_process(process)
        self.assertEqual([call.args for call in kill.call_args_list], [(1234, recovery_tui.signal.SIGTERM), (1234, recovery_tui.signal.SIGKILL)])
        self.assertEqual([call.kwargs for call in process.wait.call_args_list], [dict(timeout=15), dict(timeout=5)])


if __name__ == '__main__': unittest.main()
