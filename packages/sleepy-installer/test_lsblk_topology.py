"""Exercise real util-linux JSON topology using files, never block devices."""
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import backend
import recovery


@unittest.skipUnless(shutil.which('lsblk'), 'util-linux lsblk is required')
class LsblkTopologyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for name, minor in [('vda', 0), ('vda/vda1', 1), ('vda/vda2', 2)]:
            device = self.root / 'sys/devices/virtual/block' / name
            device.mkdir(parents=True)
            for key, value in {'dev': f'252:{minor}', 'size': '83886080', 'ro': '0',
                               'removable': '0', 'uevent': f'MAJOR=252\nMINOR={minor}\nDEVNAME={Path(name).name}\nDEVTYPE=' + ('partition' if minor else 'disk')}.items():
                (device / key).write_text(value + '\n')
            if minor: (device / 'partition').write_text(str(minor) + '\n')
            links = [('sys/dev/block', f'252:{minor}'), ('sys/class/block', Path(name).name)]
            if not minor: links.append(('sys/block', 'vda'))
            for base, key in links:
                directory = self.root / base
                directory.mkdir(parents=True, exist_ok=True)
                (directory / key).symlink_to(device)
        (self.root / 'dev').mkdir()
        (self.root / 'dev/vda').write_text('ID_PART_TABLE_TYPE=gpt\n')
        for number, filesystem, kind in [(1, 'vfat', recovery.ESP_TYPE), (2, 'btrfs', recovery.LINUX_TYPE)]:
            (self.root / f'dev/vda{number}').write_text(f'ID_FS_TYPE={filesystem}\nID_FS_UUID_ENC=uuid-{number}\nID_PART_ENTRY_TYPE={kind}\n')

    def real_lsblk(self, argv):
        # Only the data source changes: production columns and topology flags remain.
        command = [arg for arg in argv if arg != '/dev/vda']
        # The fixture contains exactly one whole disk; no real device stat is needed.
        command[command.index('blkid')] = 'file'
        return subprocess.check_output(command + ['--sysroot', str(self.root)], text=True)

    def listing(self, swaps=''):
        original_read = Path.read_text
        def read(path, *args, **kwargs):
            if path == Path('/proc/swaps'): return 'Filename Type Size Used Priority\n' + swaps
            return original_read(path, *args, **kwargs)
        with patch.object(backend, 'run', side_effect=self.real_lsblk), \
             patch.object(Path, 'is_file', return_value=True), \
             patch.object(backend.os, 'stat', return_value=SimpleNamespace(st_mode=stat.S_IFBLK)), \
             patch.object(Path, 'read_text', read):
            return backend.list_disks()[0]

    def test_actual_lsblk_retains_swap_descendant_and_uuid_identity(self):
        before = self.listing()
        self.assertTrue(before['eligible'])
        swap = self.listing('/dev/vda2 partition 1024 0 -2\n')
        self.assertFalse(swap['eligible'])
        self.assertIn('swap', swap['reason'])
        properties = self.root / 'dev/vda2'
        properties.write_text(properties.read_text().replace('uuid-2', 'changed-uuid'))
        self.assertNotEqual(before['identity'], self.listing()['identity'])

    def test_actual_lsblk_recovery_sees_two_children_not_three_roots(self):
        with patch.object(backend, 'verify_target'), patch.object(backend, 'run', side_effect=self.real_lsblk):
            self.assertEqual(recovery.partition_layout({'disk': '/dev/vda', 'identity': 'a' * 64}),
                             {'esp': '/dev/vda1', 'root': '/dev/vda2'})
