"""Validate actual Machine.boot argv without launching or touching a VM disk."""
import ast
from pathlib import Path
import tempfile
import types
import unittest


SOURCE = Path(__file__).with_name('installable-alpha.py')
TREE = ast.parse(SOURCE.read_text())
MACHINE = next(node for node in TREE.body if isinstance(node, ast.ClassDef) and node.name == 'Machine')


class BootOrder(unittest.TestCase):
    def command(self, phase, iso):
        commands = []
        namespace = {
            'subprocess': types.SimpleNamespace(Popen=lambda command, **kw: commands.append(command), STDOUT=-2),
            'QMP': lambda _: None,
        }
        exec(compile(ast.Module(body=[MACHINE], type_ignores=[]), str(SOURCE), 'exec'), namespace)
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            firmware_vars = output / 'OVMF_VARS.fd'
            firmware_vars.write_bytes(b'persistent-UEFI-variables')
            disk = output / 'installed.qcow2'
            disk.write_bytes(b'existing-installed-disk')
            machine = namespace['Machine'](output, Path('/test/OVMF_CODE.fd'), 8192, 'kvm')
            machine.boot(phase, Path('/test/installer.iso') if iso else None)
            machine.log.close()
            self.assertEqual(firmware_vars.read_bytes(), b'persistent-UEFI-variables')
            self.assertEqual(disk.read_bytes(), b'existing-installed-disk')
        return commands[0]

    def test_initial_and_recovery_media_have_explicit_priority_over_existing_disk(self):
        for phase in ('installer', 'recovery'):
            with self.subTest(phase=phase):
                command = self.command(phase, True)
                self.assertIn('virtio-blk-pci,drive=installed-disk,bootindex=2', command)
                self.assertIn('ide-cd,drive=installer-media,bus=ide.0,bootindex=1', command)
                self.assertIn('if=none,id=installer-media,format=raw,media=cdrom,readonly=on,file=/test/installer.iso', command)
                self.assertNotIn('-boot', command)
                self.assertNotIn('-cdrom', command)

    def test_disk_only_boot_has_no_installation_media_and_retains_nvram(self):
        command = self.command('offline-reboot', False)
        self.assertIn('virtio-blk-pci,drive=installed-disk,bootindex=1', command)
        self.assertFalse(any('installer-media' in item or 'installer.iso' in item for item in command))
        self.assertNotIn('-boot', command)


if __name__ == '__main__': unittest.main()
