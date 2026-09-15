import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SOURCE = Path(__file__).with_name('sleepy-system.sh')

class SystemTools(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.bin = self.root / 'bin'
        self.bin.mkdir()
        self.calls = self.root / 'calls'
        self.env = dict(os.environ, PATH=str(self.bin) + ':' + os.environ['PATH'],
                        HOME=str(self.root), XDG_STATE_HOME=str(self.root / 'state'),
                        CALLS=str(self.calls), REBUILD_STATUS='0')
        self.command('nixos-rebuild', 'printf "rebuild %s\\n" "$*" >> "$CALLS"; echo build-output; exit "$REBUILD_STATUS"')
        self.command('sudo', 'printf "sudo %s\\n" "$*" >> "$CALLS"; exec "$@"')
        self.command('nix-env', 'printf "nix-env %s\\n" "$*" >> "$CALLS"; echo "12 current"')
        self.command('readlink', 'printf "/nix/store/test-%s\\n" "${2##*/}"')
        self.command('dialog', '''printf "dialog %s\\n" "$*" >> "$CALLS"
case "$*" in
 *--menu*) printf '%s' "${CHOICE:-cancel}"; exit "${MENU_STATUS:-0}";;
 *--yesno*) exit "${CONFIRM_STATUS:-0}";;
esac''')
        self.script = self.root / 'sleepy-system'
        self.script.write_text(SOURCE.read_text().replace('@rebuild@', str(self.bin / 'nixos-rebuild')).replace('@dialogrc@', '/test/dialogrc'))

    def command(self, name, body):
        p = self.bin / name
        p.write_text('#!/usr/bin/env bash\n' + body + '\n')
        p.chmod(0o755)

    def run_tool(self, *args, **env):
        return subprocess.run(['bash', str(self.script), *args], env=self.env | env,
                              capture_output=True, text=True, timeout=5)

    def calls_text(self):
        return self.calls.read_text() if self.calls.exists() else ''

    def test_status_is_read_only_and_labels_booted_and_current(self):
        p = self.run_tool('status')
        self.assertEqual(p.returncode, 0, p.stderr)
        self.assertIn('Current system:', p.stdout)
        self.assertIn('Booted system:', p.stdout)
        self.assertNotIn('sudo', self.calls_text())

    def test_existing_rebuild_and_rollback_fixed_arguments(self):
        for name, args in [('rebuild', 'switch --flake /etc/nixos#installed'), ('rollback', 'switch --rollback')]:
            with self.subTest(name=name):
                self.calls.unlink(missing_ok=True)
                self.assertEqual(self.run_tool(name).returncode, 0)
                self.assertIn('rebuild ' + args, self.calls_text())

    def test_generations_stays_read_only(self):
        self.assertEqual(self.run_tool('generations').returncode, 0)
        self.assertIn('nix-env --list-generations -p /nix/var/nix/profiles/system', self.calls_text())
        self.assertNotIn('sudo', self.calls_text())

    def test_failed_rebuild_preserves_status_and_private_diagnostics(self):
        p = self.run_tool('rebuild', REBUILD_STATUS='17')
        self.assertEqual(p.returncode, 17)
        logs = list((self.root / 'state').rglob('*.log'))
        self.assertEqual(len(logs), 1)
        self.assertEqual(logs[0].stat().st_mode & 0o777, 0o600)
        self.assertIn('build-output', logs[0].read_text())
        self.assertIn('failed', p.stderr.lower())

    def test_default_menu_cancel_never_mutates(self):
        self.assertEqual(self.run_tool(MENU_STATUS='1').returncode, 0)
        self.assertIn('--menu', self.calls_text())
        self.assertNotIn('sudo', self.calls_text())

    def test_menu_rollback_decline_never_mutates(self):
        self.assertEqual(self.run_tool('menu', CHOICE='rollback', CONFIRM_STATUS='1').returncode, 0)
        self.assertIn('--yesno', self.calls_text())
        self.assertNotIn('sudo', self.calls_text())

    def test_broken_confirmation_dialog_is_not_silent_success(self):
        self.assertEqual(self.run_tool('menu', CHOICE='rollback', CONFIRM_STATUS='2').returncode, 2)
        self.assertNotIn('sudo', self.calls_text())

    def test_menu_rebuild_propagates_failure(self):
        self.assertEqual(self.run_tool('menu', CHOICE='rebuild', REBUILD_STATUS='23').returncode, 23)
        self.assertIn('rebuild switch --flake /etc/nixos#installed', self.calls_text())

    def test_menu_log_directory_failure_never_runs_sudo(self):
        occupied = self.root / 'occupied'
        occupied.write_text('not a directory')
        p = self.run_tool('menu', CHOICE='rebuild', XDG_STATE_HOME=str(occupied))
        self.assertNotEqual(p.returncode, 0)
        self.assertNotIn('sudo', self.calls_text())

    def test_menu_log_creation_failure_never_runs_sudo(self):
        self.command('mktemp', 'exit 19')
        p = self.run_tool('menu', CHOICE='rebuild')
        self.assertEqual(p.returncode, 19)
        self.assertNotIn('sudo', self.calls_text())

    def test_menu_status_distinguishes_same_name_different_closures(self):
        self.command('readlink', 'case "$2" in /run/current-system) echo /nix/store/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-nixos-system-sleepy;; *) echo /nix/store/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb-nixos-system-sleepy;; esac')
        p = self.run_tool('menu', CHOICE='status')
        self.assertEqual(p.returncode, 0)
        calls = self.calls_text()
        self.assertIn('nixos-system-sleepy', calls)
        self.assertIn('aaaaaaaa', calls)
        self.assertIn('bbbbbbbb', calls)

    def test_unknown_command_rejected_without_mutation(self):
        self.assertEqual(self.run_tool('arbitrary-command').returncode, 2)
        self.assertNotIn('sudo', self.calls_text())

if __name__ == '__main__':
    unittest.main()
