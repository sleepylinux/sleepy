import os
from pathlib import Path
import shutil
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
        self.profiles = self.root / 'profiles'
        self.profiles.mkdir()
        self.profile = self.profiles / 'system'
        (self.profiles / 'system-12-link').symlink_to('/nix/store/test-system')
        self.profile.symlink_to('system-12-link')
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
        self.script.write_text(SOURCE.read_text().replace('@rebuild@', str(self.bin / 'nixos-rebuild')).replace('@dialogrc@', '/test/dialogrc').replace('/nix/var/nix/profiles/system', str(self.profile)))

    def command(self, name, body):
        p = self.bin / name
        # Nix sandboxes provide Bash on PATH, without /usr/bin/env.
        bash = shutil.which('bash')
        self.assertIsNotNone(bash, 'Bash is required by the command fixtures')
        p.write_text('#!' + bash + '\n' + body + '\n')
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
        self.assertNotIn('nix-env', self.calls_text())
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

    @unittest.skipIf(os.geteuid() == 0, 'requires an actual unprivileged UID')
    def test_generations_read_root_style_readonly_profile_without_lock(self):
        # Use real readlink/stat/date and actual filesystem permission denial.
        (self.bin / 'readlink').unlink()
        (self.profiles / 'system-2-link').symlink_to('/nix/store/older-system')
        (self.profiles / 'system-bogus-link').symlink_to('/nix/store/ignore')
        (self.profiles / 'system-9-link').write_text('not a generation symlink')
        os.utime(self.profiles / 'system-2-link', (1700000000, 1700000000), follow_symlinks=False)
        os.utime(self.profiles / 'system-12-link', (1700000100, 1700000100), follow_symlinks=False)
        lock = self.profiles / 'system.lock'
        lock.write_text('unchanged')
        lock.chmod(0o444)
        self.profiles.chmod(0o555)
        self.addCleanup(self.profiles.chmod, 0o755)
        with self.assertRaises(PermissionError):
            lock.open('w')
        # Model the observed old nix-env attempt with real denied lock access.
        self.command('nix-env', 'while test "$#" -gt 0; do if test "$1" = -p; then shift; : > "$1.lock"; exit; fi; shift; done')
        before = {p.name: p.lstat().st_mtime_ns for p in self.profiles.iterdir()}
        result = self.run_tool('generations', TZ='UTC')
        self.assertEqual(result.returncode, 0, result.stderr)
        rows = result.stdout.strip().splitlines()
        self.assertEqual([r.split()[0] for r in rows], ['2', '12'])
        self.assertIn('2023-11-14 22:13:20', rows[0])
        self.assertNotIn('(current)', rows[0])
        self.assertIn('(current)', rows[1])
        menu = self.run_tool('menu', CHOICE='generations', TZ='UTC')
        self.assertEqual(menu.returncode, 0, menu.stderr)
        self.assertIn('(current)', self.calls_text())
        self.assertEqual({p.name: p.lstat().st_mtime_ns for p in self.profiles.iterdir()}, before)
        self.assertEqual(lock.read_text(), 'unchanged')
        self.assertNotIn('sudo', self.calls_text())

    def test_unknown_command_rejected_without_mutation(self):
        self.assertEqual(self.run_tool('arbitrary-command').returncode, 2)
        self.assertNotIn('sudo', self.calls_text())

if __name__ == '__main__':
    unittest.main()
