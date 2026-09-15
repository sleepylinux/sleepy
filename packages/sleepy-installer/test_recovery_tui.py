import subprocess
import unittest
from unittest.mock import Mock, patch

import recovery_tui


class Dialog:
    def __init__(self, answers): self.answers = iter(answers); self.prompts = []; self.messages = []
    def ask(self, title, kind, text, *items, **options):
        self.prompts.append((title, text, options)); return next(self.answers)
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

    def test_child_cleanup_grace_exceeds_backend_grace_then_reaps(self):
        process = Mock(pid=1234)
        process.poll.return_value = None
        process.wait.side_effect = [subprocess.TimeoutExpired('sudo', 15), 0]
        with patch.object(recovery_tui.os, 'killpg') as kill:
            recovery_tui.stop_process(process)
        self.assertEqual([call.args for call in kill.call_args_list], [(1234, recovery_tui.signal.SIGTERM), (1234, recovery_tui.signal.SIGKILL)])
        self.assertEqual([call.kwargs for call in process.wait.call_args_list], [dict(timeout=15), dict(timeout=5)])


if __name__ == '__main__': unittest.main()
