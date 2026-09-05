#!/usr/bin/env python3
"""Behavior checks; the fake executable records the process boundary, never touches Nix."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

CLI = Path(__file__).resolve().parents[1] / 'packages/snug/snug.py'


class SnugTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.log = self.root / 'calls'
        self.environment_log = self.root / 'environments'
        bin_dir = self.root / 'bin'
        bin_dir.mkdir()
        nix = bin_dir / 'nix'
        nix.write_text('#!' + sys.executable + '''
import json, os, sys
from pathlib import Path
with open(os.environ['CALLS'], 'a') as f: f.write(json.dumps(sys.argv[1:]) + '\\n')
with open(os.environ['ENV_CALLS'], 'a') as f: f.write(json.dumps({'NIXPKGS_ALLOW_UNFREE': os.environ.get('NIXPKGS_ALLOW_UNFREE')}) + '\\n')
if os.environ.get('NIX_FAIL'): sys.exit(int(os.environ['NIX_FAIL']))
if 'list' in sys.argv and '--json' in sys.argv: print(os.environ.get('PROFILE_JSON', '{"elements":{}}'))
if 'lock' in sys.argv or 'update' in sys.argv and 'flake' in sys.argv:
    Path('flake.lock').write_text('{"version":7}')
''')
        nix.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.root), XDG_STATE_HOME=str(self.root / 'state'),
                        XDG_DATA_HOME=str(self.root / 'data'),
                        PATH=str(bin_dir) + os.pathsep + os.environ['PATH'], CALLS=str(self.log), ENV_CALLS=str(self.environment_log))
        self.env.pop('NIXPKGS_ALLOW_UNFREE', None)

    def run_cli(self, *args, **kwargs):
        return subprocess.run([sys.executable, str(CLI), *args], env=self.env,
                              cwd=self.root, text=True, capture_output=True, **kwargs)

    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def test_short_install_uses_isolated_profile_and_rolling_source(self):
        result = self.run_cli('-i', 'vim', 'ripgrep')
        self.assertEqual(result.returncode, 0, result.stderr)
        args = self.calls()[-1]
        self.assertIn('profile', args)
        self.assertIn('install', args)
        self.assertIn(str(self.root / 'state/snug/profile'), args)
        self.assertIn('github:NixOS/nixpkgs/nixos-unstable#vim', args)
        self.assertIn('github:NixOS/nixpkgs/nixos-unstable#ripgrep', args)

    def test_backend_failure_is_not_success(self):
        self.env['NIX_FAIL'] = '42'
        result = self.run_cli('-i', 'vim')
        self.assertEqual(result.returncode, 42)
        self.assertNotIn('installed', result.stdout.lower())

    def test_rejects_option_and_expression_injection(self):
        for name in ['--impure', 'vim; touch stolen', '$(touch stolen)', '../vim', 'vim#x']:
            with self.subTest(name=name):
                result = self.run_cli('-i', '--', name)
                self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertFalse((self.root / 'stolen').exists())

    def test_update_and_rollback_use_personal_profile(self):
        self.assertEqual(self.run_cli('-u').returncode, 0)
        self.assertIn('--all', self.calls()[-1])
        self.assertEqual(self.run_cli('-b').returncode, 0)
        self.assertIn('rollback', self.calls()[-1])

    def test_shell_command_arguments_remain_literal(self):
        result = self.run_cli('-e', 'git', '--', 'printf', '%s', '$(touch stolen)')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1][-4:], ['--command', 'printf', '%s', '$(touch stolen)'])
        self.assertFalse((self.root / 'stolen').exists())

    def test_dev_init_creates_reproducible_project(self):
        result = self.run_cli('-d', 'init', 'python', 'project')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / 'project/flake.lock').exists())
        self.assertIn('python3', (self.root / 'project/flake.nix').read_text())

    def test_dev_init_preserves_existing_files(self):
        project = self.root / 'project'
        project.mkdir()
        (project / 'flake.nix').write_text('user config')
        result = self.run_cli('-d', 'init', 'python', 'project')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((project / 'flake.nix').read_text(), 'user config')
        self.assertEqual(self.calls(), [])

    def test_dev_failure_removes_only_own_generated_files(self):
        project = self.root / 'project'
        project.mkdir()
        (project / 'notes').write_text('keep')
        self.env['NIX_FAIL'] = '1'
        result = self.run_cli('-d', 'init', 'rust', 'project')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse((project / 'flake.nix').exists())
        self.assertEqual((project / 'notes').read_text(), 'keep')

    def test_remove_nested_attribute_resolves_real_profile_name(self):
        self.env['PROFILE_JSON'] = json.dumps({'elements': {'requests': {
            'attrPath': 'legacyPackages.x86_64-linux.python3Packages.requests',
            'originalUrl': 'github:NixOS/nixpkgs/nixos-unstable'}}})
        result = self.run_cli('-r', 'python3Packages.requests')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1][-2:], ['--', 'requests'])

    def test_remove_unknown_package_is_error(self):
        result = self.run_cli('-r', 'not-installed')
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any('remove' in call for call in self.calls()))
        self.assertNotIn('Traceback', result.stderr)

    def test_dev_unknown_preset_has_no_traceback(self):
        result = self.run_cli('-d', 'init', 'unknown')
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn('Traceback', result.stderr)

    def test_temporary_install_and_long_aliases(self):
        for flags in [('-it',), ('-ti',), ('--install', '--temporary'), ('install', '-t')]:
            with self.subTest(flags=flags):
                result = self.run_cli(*flags, 'vim', '--', 'vim', '--version')
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn('shell', self.calls()[-1])
                self.assertNotIn('profile', self.calls()[-1])
                self.assertEqual(self.calls()[-1][-3:], ['--command', 'vim', '--version'])
        self.assertFalse((self.root / 'state/snug/profile').exists())

    def test_long_update_alias(self):
        self.assertEqual(self.run_cli('--update').returncode, 0)
        self.assertIn('upgrade', self.calls()[-1])

    def test_nix_passthrough_preserves_full_arguments(self):
        result = self.run_cli('nix', 'eval', '--expr', '{ answer = 42; }', '--json')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1][-4:], ['eval', '--expr', '{ answer = 42; }', '--json'])

    def test_nix_help_is_forwarded(self):
        self.assertEqual(self.run_cli('nix', '--help').returncode, 0)
        self.assertEqual(self.calls()[-1][-1], '--help')

    def test_help_documents_temporary_and_long_flags(self):
        result = self.run_cli('--help')
        self.assertEqual(result.returncode, 0)
        self.assertIn('--install', result.stdout)
        self.assertIn('-it', result.stdout)
        self.assertEqual(self.calls(), [])

    def test_conflicting_actions_are_rejected(self):
        result = self.run_cli('-i', 'vim', '-u')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])

    def test_unfree_opt_in_reaches_each_supported_nix_operation(self):
        for arguments, operation in [
            (('-i', '--unfree', 'steam'), 'install'),
            (('-it', '--unfree', 'steam', '--', 'steam', '--version'), 'shell'),
            (('-x', '--unfree', 'steam', '--', '--version'), 'run'),
            (('-e', '--unfree', 'steam', '--', 'steam', '--version'), 'shell'),
            (('-s', '--unfree', 'steam'), 'search'),
            (('-u', '--unfree'), 'upgrade'),
        ]:
            with self.subTest(arguments=arguments):
                result = self.run_cli(*arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(operation, self.calls()[-1])
                self.assertIn('--impure', self.calls()[-1])
                self.assertLess(self.calls()[-1].index(operation), self.calls()[-1].index('--impure'))
                self.assertNotIn('--unfree', self.calls()[-1])
                environment = json.loads(self.environment_log.read_text().splitlines()[-1])
                self.assertEqual(environment['NIXPKGS_ALLOW_UNFREE'], '1')

    def test_ordinary_commands_do_not_enable_unfree(self):
        result = self.run_cli('-i', 'vim')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn('--impure', self.calls()[-1])
        environment = json.loads(self.environment_log.read_text().splitlines()[-1])
        self.assertIsNone(environment['NIXPKGS_ALLOW_UNFREE'])

    def test_unfree_environment_is_scoped_to_the_subprocess(self):
        spec = importlib.util.spec_from_file_location('snug_unfree_test', CLI)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        before = dict(os.environ)
        with patch.object(module, 'run') as execute:
            module.main(['-it', '--unfree', 'steam'])
            opted_in = execute.call_args
            module.main(['-it', 'vim'])
            ordinary = execute.call_args
        self.assertEqual(os.environ, before)
        self.assertEqual(opted_in.kwargs['env']['NIXPKGS_ALLOW_UNFREE'], '1')
        self.assertNotIn('env', ordinary.kwargs)
        self.assertNotIn('--impure', ordinary.args[0])

    def test_unfree_never_enables_system_update_or_consumes_app_flags(self):
        rejected = self.run_cli('-u', '--system', '--unfree')
        self.assertNotEqual(rejected.returncode, 0)
        self.assertEqual(self.calls(), [])
        forwarded = self.run_cli('-x', 'hello', '--', '--unfree')
        self.assertEqual(forwarded.returncode, 0, forwarded.stderr)
        self.assertEqual(self.calls()[-1][-2:], ['--', '--unfree'])
        self.assertNotIn('--impure', self.calls()[-1])

    def test_unfree_failure_preserves_backend_status(self):
        self.env['NIX_FAIL'] = '42'
        failed = self.run_cli('-i', '--unfree', 'steam')
        self.assertEqual(failed.returncode, 42)

    def test_dev_requires_existing_project(self):
        result = self.run_cli('-d')
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.calls(), [])


if __name__ == '__main__':
    unittest.main()
