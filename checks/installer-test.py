#!/usr/bin/env python3
"""Installer safety tests. All execution uses fake commands and temporary paths."""
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('sleepy_installer', Path(__file__).resolve().parents[1] / 'packages/sleepy-installer/installer.py')
installer = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = installer
spec.loader.exec_module(installer)

DISK = {'name': '/dev/vda', 'type': 'disk', 'size': 64*1024**3, 'model': 'TEST ONLY',
        'serial': 'test-disposable-001', 'wwn': None, 'maj:min': '252:0', 'ro': False, 'mountpoints': [None]}

class FakeRunner:
    def __init__(self, fail=None):
        self.commands = []
        self.secrets = []
        self.fail = fail
        self.messages = []
    def progress(self, message):
        self.messages.append(message)
    def run(self, argv, secret=None):
        self.commands.append(argv)
        if secret is not None:
            self.secrets.append(secret)
        if argv[0] == self.fail:
            raise installer.InstallError('simulated failure')
        if '--output-lock-file' in argv:
            Path(argv[argv.index('--output-lock-file') + 1]).write_text('{"preflight": true}')
        return ''

class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.source = self.base/'source'
        self.source.mkdir()
        (self.source/'flake.nix').write_text('{}')
        (self.source/'flake.lock').write_text('{}')
        self.plan = installer.Plan(copy.deepcopy(DISK))
        self.runner = FakeRunner()

    def execute(self, **kwargs):
        arguments = dict(plan=self.plan, password='safe test password', confirmation='ERASE /dev/vda',
                         source=self.source, target=str(self.base/'target'), runner=self.runner,
                         scanner=lambda: [copy.deepcopy(DISK)], boot_resolver=lambda path: '/dev/vda')
        arguments.update(kwargs)
        return installer.execute(**arguments)

    def test_live_media_and_deep_mounted_descendants_rejected(self):
        for mount in ['/iso', '/', '[SWAP]', '/mnt']:
            disk = copy.deepcopy(DISK)
            disk['children'] = [{'children': [{'mountpoints': [mount]}]}]
            self.assertIn('Mounted', installer.unsafe_reason(disk))
            self.plan.disk = disk
            with self.assertRaises(installer.InstallError):
                self.execute()
            self.assertEqual(self.runner.commands, [])

    def test_readonly_small_ambiguous_and_partition_disks_rejected(self):
        for change in [{'ro': True}, {'size': 1024}, {'serial': None}, {'type': 'part'}, {'name': '/dev/a;reboot'}]:
            self.plan.disk = dict(DISK, **change)
            with self.assertRaises(installer.InstallError):
                self.execute()
            self.assertEqual(self.runner.commands, [])

    def test_confirmation_is_exact_and_rescan_binds_entire_inventory(self):
        with self.assertRaises(installer.InstallError):
            self.execute(confirmation='/dev/vda')
        for change in [{'serial': 'replacement'}, {'size': 65*1024**3}, {'maj:min': '253:0'}, {'children': [{'mountpoints': ['/mnt']}]}]:
            with self.assertRaises(installer.InstallError):
                self.execute(scanner=lambda: [dict(DISK, **change)])
        self.assertEqual(self.runner.commands, [])

    def test_allowlist_and_untrusted_fields_cannot_become_nix(self):
        for key, value in [('packages', ['hello; builtins.abort "bad"']), ('hostname', '${bad}'), ('username', 'root'), ('gpu', 'fake'), ('timezone', '";evil'), ('keyboard', 'evil')]:
            plan = installer.Plan(copy.deepcopy(DISK))
            setattr(plan, key, value)
            with self.assertRaises(installer.InstallError):
                installer.config_text(plan)
        self.assertNotIn('password', installer.config_text(self.plan).lower().replace('hashedpassword', ''))

    def test_uefi_success_order_password_stdin_and_cleanup(self):
        self.execute()
        commands = self.runner.commands
        self.assertEqual(next(c for c in commands if c[0] == 'parted'), ['parted', '--script', '/dev/vda', 'mklabel', 'gpt'])
        self.assertIn(['mkfs.fat', '-F', '32', '/dev/vda1'], commands)
        self.assertTrue(commands[-2][-1].endswith('/boot'))
        self.assertEqual(commands[-1][0], 'umount')
        self.assertEqual(self.runner.secrets, ['sleepy:safe test password\n'])
        self.assertNotIn('safe test password', json.dumps(commands))
        for path in (self.base/'target/etc/nixos').iterdir():
            self.assertNotIn('safe test password', path.read_text())
        self.assertIn('sleepy.lib.mkSleepyHost', (self.base/'target/etc/nixos/flake.nix').read_text())

    def test_mount_uses_the_formatted_type_without_stale_autodetection(self):
        self.execute()
        mounts = [args for args in self.runner.commands if args[0] == 'mount']
        self.assertEqual(mounts, [
            ['mount', '-t', 'ext4', '/dev/vda2', str(self.base / 'target')],
            ['mount', '-t', 'vfat', '/dev/vda1', str(self.base / 'target/boot')],
        ])

    def test_source_build_concurrency_is_bounded_in_the_live_environment(self):
        self.execute()
        command = next(args for args in self.runner.commands if args[0] == 'nixos-install')
        self.assertEqual(command[command.index('--max-jobs') + 1], '1')
        self.assertEqual(command[command.index('--cores') + 1], '1')

    def test_russian_keyboard_keeps_latin_input_and_a_switch_shortcut(self):
        self.plan.keyboard = 'ru'
        configuration = installer.config_text(self.plan)
        self.assertIn('kb_layout = lib.mkForce "us,ru";', configuration)
        self.assertIn('kb_options = lib.mkForce "grp:alt_shift_toggle";', configuration)
        self.assertIn('services.xserver.xkb.layout = lib.mkForce "us,ru";', configuration)
        self.assertIn('services.xserver.xkb.options = lib.mkForce "grp:alt_shift_toggle";', configuration)
        self.plan.keyboard = 'fr'
        self.assertIn('kb_layout = lib.mkForce "fr";', installer.config_text(self.plan))

    def test_bios_and_nvme_partitions(self):
        self.plan.firmware = 'bios'
        self.plan.boot_device = '/dev/disk/by-id/virtio-test-disposable-001'
        self.execute()
        self.assertFalse(any(c[0] == 'mkfs.fat' for c in self.runner.commands))
        self.assertTrue(any('bios_grub' in c for c in self.runner.commands))
        self.assertEqual(installer.partition_path('/dev/nvme0n1', 2), '/dev/nvme0n1p2')
        self.assertIn('boot.loader.grub', installer.config_text(self.plan))

    def test_failures_stop_forward_execution_and_only_cleanup_owned_mounts(self):
        for command in ['parted', 'mkfs.ext4', 'mount', 'nixos-generate-config', 'nix', 'nixos-install', 'nixos-enter']:
            with self.subTest(command=command):
                runner = FakeRunner(fail=command)
                target = str(self.base/command)
                with self.assertRaises(installer.InstallError):
                    self.execute(runner=runner, target=target)
                failed = next(i for i,c in enumerate(runner.commands) if c[0] == command)
                self.assertTrue(all(c[0] == 'umount' for c in runner.commands[failed+1:]))
                for c in runner.commands[failed+1:]:
                    self.assertIn(c[1], [target, target+'/boot'])

    def test_busy_target_and_missing_source_fail_before_mutation(self):
        busy = self.base/'busy'
        busy.mkdir()
        (busy/'keep').write_text('keep')
        for kwargs in [{'target': str(busy)}, {'source': self.base/'missing'}]:
            with self.assertRaises(installer.InstallError):
                self.execute(**kwargs)
        self.assertEqual(self.runner.commands, [])

    def test_password_failure_redacts_command_output(self):
        output = subprocess.CompletedProcess([], 1, 'do not expose secret-password')
        messages = []
        with patch.object(installer.subprocess, 'run', return_value=output) as run:
            with self.assertRaises(installer.InstallError) as error:
                installer.Runner(messages.append).run(['chpasswd'], secret='secret-password')
        self.assertNotIn('secret-password', str(error.exception))
        self.assertNotIn('secret-password', str(messages))
        self.assertEqual(run.call_args.kwargs['input'], 'secret-password')

    def test_command_output_streams_and_failures_have_bounded_diagnostics(self):
        messages = []
        runner = installer.Runner(messages.append)
        self.assertEqual(runner.run([sys.executable, '-c', 'print("download progress")']), 'download progress\n')
        self.assertIn('download progress', messages)
        with self.assertRaises(installer.InstallError) as error:
            runner.run([sys.executable, '-c', 'print("x" * 20000); raise SystemExit(7)'])
        self.assertIn('Command failed (7)', str(error.exception))
        self.assertLess(len(str(error.exception)), 3200)

    def test_initial_source_override_persists_the_lock(self):
        self.execute()
        lock = next(c for c in self.runner.commands if c[0] == 'nix' and 'lock' in c)
        self.assertTrue(lock[lock.index('--output-lock-file') + 1].endswith('/flake.lock'))
        self.assertEqual((self.base/'target/etc/nixos/flake.lock').read_text(), '{"preflight": true}')
        self.assertFalse(Path(lock[lock.index('--output-lock-file') + 1]).exists())
        self.assertEqual(lock[lock.index('--override-input') + 1:lock.index('--override-input') + 3],
                         ['sleepy', 'path:' + str(self.source.resolve())])

    def test_prime_decimal_bus_ids_and_ambiguous_hardware(self):
        pci = '0000:0a:1f.2 0302: 10de:1234\n0000:00:02.0 0300: 8086:4321'
        self.assertEqual(installer.prime_devices(pci), {'nvidiaBusId': 'PCI:10:31:2', 'intelBusId': 'PCI:0:2:0'})
        self.assertEqual(installer.prime_devices(pci.replace('8086:', '1002:'))['amdgpuBusId'], 'PCI:0:2:0')
        self.assertIsNone(installer.prime_devices(pci + '\n0000:0b:00.0 0300: 10de:4567'))
        self.assertIsNone(installer.prime_devices(pci.replace('0000:0a', '0001:0a')))
        self.assertIsNone(installer.prime_devices('0000:01:00.0 0300: 10de:1234'))

    def test_nvidia_choice_and_prime_are_generated_and_validated(self):
        self.plan.gpu = 'nvidia'
        self.plan.nvidia_open = True
        self.plan.nvidia_mode = 'offload'
        self.plan.prime = {'nvidiaBusId': 'PCI:10:0:0', 'intelBusId': 'PCI:0:2:0'}
        configuration = installer.config_text(self.plan)
        self.assertIn('sleepy.hardware.nvidia.open = true;', configuration)
        self.assertIn('sleepy.hardware.nvidia.mode = "offload";', configuration)
        self.assertIn('sleepy.hardware.nvidia.nvidiaBusId = "PCI:10:0:0";', configuration)
        self.assertEqual(self.plan.manifest()['prime'], self.plan.prime)
        self.plan.prime['intelBusId'] = '"; builtins.abort "bad"'
        with self.assertRaises(installer.InstallError):
            installer.config_text(self.plan)
        self.plan.prime = {'nvidiaBusId': 'PCI:10:0:0'}
        with self.assertRaises(installer.InstallError):
            installer.config_text(self.plan)

    def test_typo_and_password_retries_preserve_onboarding(self):
        ui = installer.UI.__new__(installer.UI)
        ui.step = 10
        with patch.object(ui, 'prompt', side_effect=['bad hostname!', 'good-host']) as prompt:
            self.assertEqual(ui.validated_prompt('Computer', 'hostname'), 'good-host')
            self.assertEqual(prompt.call_count, 2)
            self.assertEqual(prompt.call_args.kwargs['default'], 'bad hostname!')
        with patch.object(ui, 'prompt', side_effect=['short', 'long enough', 'different', 'correct password', 'correct password']), patch.object(ui, 'message') as message:
            self.assertEqual(ui.password(), 'correct password')
            message.assert_called_once()

    def test_reserved_system_accounts_rejected_before_commands(self):
        for name in ['messagebus', 'systemd-network', 'nixbld1', 'polkituser', 'mysql', 'sshd']:
            self.plan.username = name
            with self.assertRaises(installer.InstallError):
                self.execute()
        self.assertEqual(self.runner.commands, [])

    def test_preflight_eval_failure_never_reaches_disk_commands(self):
        class FailedEvaluation(FakeRunner):
            def run(self, argv, secret=None):
                result = super().run(argv, secret)
                if 'eval' in argv:
                    raise installer.InstallError('configuration assertion failed')
                return result
        runner = FailedEvaluation()
        with self.assertRaises(installer.InstallError):
            self.execute(runner=runner)
        self.assertTrue(all(c[0] == 'nix' for c in runner.commands))
        self.assertFalse((self.base/'target').exists())

    def test_disk_rescan_after_preflight_is_last_before_partitioning(self):
        snapshots = iter([[copy.deepcopy(DISK)], [dict(DISK, serial='replacement-after-fetch')]])
        with self.assertRaises(installer.InstallError):
            self.execute(scanner=lambda: next(snapshots))
        self.assertTrue(any('eval' in c for c in self.runner.commands))
        self.assertFalse(any(c[0] == 'parted' for c in self.runner.commands))

    def test_bios_grub_target_is_persistent_and_not_enumeration_path(self):
        self.plan.firmware = 'bios'
        self.plan.boot_device = '/dev/disk/by-id/wwn-0x123456'
        config = installer.config_text(self.plan)
        self.assertIn('boot.loader.grub.device = "/dev/disk/by-id/wwn-0x123456";', config)
        self.assertNotIn('boot.loader.grub.device = "/dev/vda"', config)
        self.assertEqual(self.plan.manifest()['bootDevice'], self.plan.boot_device)
        self.plan.boot_device = ''
        with self.assertRaises(installer.InstallError):
            self.execute()
        self.assertEqual(self.runner.commands, [])

    def test_boot_id_retargeting_rejected_before_disk_mutation(self):
        self.plan.firmware = 'bios'
        self.plan.boot_device = '/dev/disk/by-id/wwn-0x123456'
        with self.assertRaises(installer.InstallError):
            self.execute(boot_resolver=lambda path: '/dev/vdb')
        self.assertEqual(self.runner.commands, [])
        resolutions = iter(['/dev/vda', '/dev/vdb'])
        with self.assertRaises(installer.InstallError):
            self.execute(boot_resolver=lambda path: next(resolutions))
        self.assertFalse(any(c[0] == 'parted' for c in self.runner.commands))

    def test_by_id_discovery_uses_existing_matching_whole_disk_symlinks(self):
        devices = self.base/'devices'
        devices.mkdir()
        disk = devices/'disk'
        disk.touch()
        other = devices/'other'
        other.touch()
        directory = self.base/'by-id'
        directory.mkdir()
        (directory/'ata-disk').symlink_to(disk)
        (directory/'wwn-correct').symlink_to(disk)
        (directory/'wwn-correct-part1').symlink_to(disk)
        (directory/'wwn-wrong').symlink_to(other)
        (directory/'wwn-broken').symlink_to(devices/'missing')
        self.assertEqual(installer.disk_by_id({'name': str(disk)}, directory), str(directory/'wwn-correct'))
        self.assertEqual(installer.disk_by_id({'name': '/dev/not-real'}, directory), '')

    def test_gpu_detection(self):
        for pci, expected in [('0000:00:02.0 0300: 8086:1234 (rev 01)', 'intel'),
                              ('0000:01:00.0 0302: 10de:1234', 'nvidia'),
                              ('0000:00:02.0 0300: 8086:1234\n0000:01:00.0 0300: 10de:1234', 'auto')]:
            with patch.object(installer.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, pci)):
                self.assertEqual(installer.detected_gpu()[0], expected)

if __name__ == '__main__':
    unittest.main()
