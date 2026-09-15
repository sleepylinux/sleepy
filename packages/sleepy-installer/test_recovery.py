import json
from contextlib import contextmanager, nullcontext
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import backend
import recovery


class RecoveryMetadataTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.target = '/nix/store/' + 'a' * 32 + '-nixos-system-sleepy-26.11'
        system = self.root / self.target.lstrip('/')
        (system / 'bin').mkdir(parents=True)
        (system / 'etc').mkdir()
        (system / 'etc/os-release').write_text('ID=sleepy\nVERSION="26.11"\n')
        (system / 'bin/switch-to-configuration').write_text('#!/bin/sh\nexit 0\n')
        (system / 'bin/switch-to-configuration').chmod(0o755)
        profiles = self.root / 'nix/var/nix/profiles'
        profiles.mkdir(parents=True)
        (profiles / 'system-1-link').symlink_to(self.target)
        (profiles / 'system').symlink_to('system-1-link')
        (self.root / 'etc').mkdir()
        (self.root / 'etc/os-release').symlink_to(self.target + '/etc/os-release')
        for name in ('boot', 'dev', 'sys', 'proc', 'run'): (self.root / name).mkdir()

    def test_absolute_installed_links_resolve_inside_mounted_root(self):
        self.assertEqual(recovery.rooted(self.root, '/etc/os-release'), self.root / self.target.lstrip('/') / 'etc/os-release')
        metadata = recovery.inspect_installation(self.root)
        self.assertEqual(metadata['current'], 1)
        self.assertEqual(metadata['generations'][0]['system'], self.target)

    def test_double_slash_absolute_link_stays_inside_installed_root(self):
        (self.root / 'double').symlink_to('//etc/os-release')
        expected = self.root / self.target.lstrip('/') / 'etc/os-release'
        self.assertEqual(recovery.rooted(self.root, '/double'), expected)

    def test_current_generation_uses_link_number_even_for_identical_targets(self):
        (self.root / 'nix/var/nix/profiles/system-2-link').symlink_to(self.target)
        self.assertEqual(recovery.inspect_installation(self.root)['current'], 1)

    def test_dev_mountpoint_symlink_is_rejected(self):
        (self.root / 'dev').rmdir(); (self.root / 'dev').symlink_to('/etc')
        with self.assertRaises(backend.InstallError): recovery.inspect_installation(self.root)

    def test_traversal_and_symlink_loop_are_rejected(self):
        with self.assertRaises(backend.InstallError): recovery.rooted(self.root, '../../etc/passwd')
        (self.root / 'loop').symlink_to('/loop')
        with self.assertRaises(backend.InstallError): recovery.rooted(self.root, '/loop')
        (self.root / 'escape').symlink_to('../../outside')
        with self.assertRaises(backend.InstallError): recovery.rooted(self.root, '/escape')

    def test_non_sleepy_and_changed_repair_program(self):
        before = recovery.inspect_installation(self.root)['installation']
        program = self.root / self.target.lstrip('/') / 'bin/switch-to-configuration'
        program.write_text('#!/bin/sh\nexit 2\n')
        self.assertNotEqual(before, recovery.inspect_installation(self.root)['installation'])
        (self.root / self.target.lstrip('/') / 'etc/os-release').write_text('ID=nixos\n')
        with self.assertRaises(backend.InstallError): recovery.inspect_installation(self.root)

    def test_current_profile_must_be_retained_store_generation(self):
        profile = self.root / 'nix/var/nix/profiles/system'
        profile.unlink(); profile.symlink_to('/etc')
        with self.assertRaises(backend.InstallError): recovery.inspect_installation(self.root)

    def test_boot_mountpoint_symlink_is_rejected(self):
        (self.root / 'boot').rmdir(); (self.root / 'boot').symlink_to('/etc')
        with self.assertRaises(backend.InstallError): recovery.inspect_installation(self.root)

    def test_readonly_inspection_does_not_modify_installed_tree(self):
        before = {str(p.relative_to(self.root)): (p.lstat().st_mtime_ns, p.lstat().st_size) for p in self.root.rglob('*')}
        recovery.inspect_installation(self.root)
        after = {str(p.relative_to(self.root)): (p.lstat().st_mtime_ns, p.lstat().st_size) for p in self.root.rglob('*')}
        self.assertEqual(before, after)


class RecoveryRequestTests(unittest.TestCase):
    def setUp(self):
        self.request = {'disk': '/dev/vda', 'identity': 'a' * 64}
        self.layout = {'path': '/dev/vda', 'type': 'disk', 'pttype': 'gpt', 'children': [
            {'path': '/dev/vda1', 'type': 'part', 'fstype': 'vfat', 'parttype': recovery.ESP_TYPE, 'uuid': 'ABCD-1234'},
            {'path': '/dev/vda2', 'type': 'part', 'fstype': 'btrfs', 'parttype': recovery.LINUX_TYPE, 'uuid': '12345678-1234-1234-1234-123456789abc'}]}

    def test_no_ui_command_or_unconfirmed_restore(self):
        with self.assertRaises(backend.InstallError): recovery.validate_request(dict(self.request, command='sh'), False)
        with self.assertRaises(backend.InstallError): recovery.validate_request(dict(self.request, installation='b' * 64, confirm_restore='/dev/vdb'), True)

    def test_only_exact_two_partition_layout(self):
        with patch.object(backend, 'verify_target'), patch.object(backend, 'run', side_effect=lambda _: json.dumps({'blockdevices': [self.layout]})):
            self.assertEqual(recovery.partition_layout(self.request)['root'], '/dev/vda2')
            self.layout['children'].append(dict(self.layout['children'][1], path='/dev/vda3'))
            with self.assertRaises(backend.InstallError): recovery.partition_layout(self.request)

    def test_luks2_locked_inspection_needs_no_passphrase_and_never_mounts(self):
        self.layout['children'][1]['fstype']='crypto_LUKS'
        with patch.object(backend,'verify_target'), patch.object(backend,'run',return_value=json.dumps({'blockdevices':[self.layout]})):
            layout=recovery.partition_layout(self.request)
        self.assertEqual(layout['luks_uuid'],self.layout['children'][1]['uuid'])
        with patch.object(recovery,'recovery_lock',return_value=nullcontext()), patch.object(recovery,'partition_layout',return_value=layout), patch.object(recovery,'mounted_root') as mount:
            result=recovery.recover(self.request)
            self.assertTrue(result['locked'])
            self.assertTrue(result['encrypted'])
            self.assertNotIn('installation',result)
            mount.assert_not_called()

    def test_recovery_passphrase_uses_same_console_contract(self):
        request=dict(self.request,encryption_passphrase='Correct Horse 123')
        self.assertEqual(recovery.validate_request(request,False),request)
        for value in ['short','Unicodeé'*3,'with\nnewline12']:
            with self.assertRaises(backend.InstallError):
                recovery.validate_request(dict(request,encryption_passphrase=value),False)

    def test_busy_target_rejected_before_mount_or_layout_command(self):
        with patch.object(backend, 'verify_target', side_effect=backend.InstallError('busy')), patch.object(backend, 'run') as run:
            with self.assertRaises(backend.InstallError): recovery.partition_layout(self.request)
            run.assert_not_called()


class RecoveryMountTests(unittest.TestCase):
    def test_mount_completed_then_interrupted_is_unmounted(self):
        mounted = False
        commands = []
        def run(argv):
            nonlocal mounted
            commands.append(argv)
            if argv[0] == 'mount':
                mounted = True
                raise backend.InstallError('interrupted after mount completed')
            mounted = False
        with patch.object(recovery.os.path, 'ismount', side_effect=lambda _: mounted), patch.object(backend, 'run', side_effect=run):
            with self.assertRaises(backend.InstallError):
                with recovery.mounted_root({'root': '/dev/vda2'}): self.fail('must not enter')
        self.assertFalse(mounted)
        self.assertEqual(commands[-1], ['umount', '--recursive', str(recovery.ROOT)])
        self.assertIn('ro,rescue=nologreplay,nosuid,nodev,noexec', commands[0])

    def test_preexisting_mount_is_never_unmounted(self):
        with patch.object(recovery.os.path, 'ismount', return_value=True), patch.object(backend, 'run') as run:
            with self.assertRaises(backend.InstallError):
                with recovery.mounted_root({'root': '/dev/vda2'}): self.fail('must not enter')
            run.assert_not_called()


class EncryptedRecoveryTests(unittest.TestCase):
    def setUp(self):
        self.uuid='12345678-1234-4234-8234-123456789abc'
        self.layout={'root':'/dev/vda2','esp':'/dev/vda1','luks_uuid':self.uuid}
        self.passphrase='Correct Horse 123'

    def exercise(self, wrong=False, cancel=False, unmount_failure=False, writable=False):
        calls=[]
        state={'mounted':False,'mapped':False}
        def command(argv, secret=None):
            calls.append((argv,secret))
            if argv[0]=='blkid': return self.uuid if 'UUID' in argv else 'btrfs'
            if argv[:2]==['cryptsetup','open']:
                if wrong: raise backend.InstallError('cryptsetup failed (exit 2)')
                state['mapped']=True
            if argv[0]=='mount': state['mounted']=True
            if argv[0]=='umount':
                if unmount_failure: raise backend.InstallError('busy')
                state['mounted']=False
            if argv[:2]==['cryptsetup','close']: state['mapped']=False
            return ''
        with patch.object(backend,'run',side_effect=command), patch.object(backend.os.path,'lexists',side_effect=lambda _:state['mapped']), patch.object(recovery.os.path,'ismount',side_effect=lambda _:state['mounted']), patch.object(recovery.RecoveryLuksRoot,'owned',return_value=True):
            if wrong or cancel or unmount_failure:
                with self.assertRaises(backend.InstallError):
                    with recovery.mounted_root(self.layout,writable=writable,passphrase=self.passphrase):
                        if cancel: raise backend.InstallError('cancelled')
            else:
                with recovery.mounted_root(self.layout,writable=writable,passphrase=self.passphrase): pass
        return calls,state

    def test_wrong_passphrase_never_mounts_or_repairs(self):
        calls,state=self.exercise(wrong=True)
        self.assertFalse(state['mapped'])
        self.assertFalse(any(argv[0] in ['mount','chroot'] for argv,_ in calls))
        self.assertFalse(any(argv[:2]==['cryptsetup','close'] for argv,_ in calls))

    def test_inspection_unlock_is_readonly_and_cancel_closes_after_unmount(self):
        for cancel in [False,True]:
            calls,state=self.exercise(cancel=cancel)
            self.assertFalse(state['mapped'])
            self.assertFalse(state['mounted'])
            open_args=next(argv for argv,_ in calls if argv[:2]==['cryptsetup','open'])
            self.assertIn('--readonly',open_args)
            self.assertEqual(calls[-2][0][0],'umount')
            self.assertEqual(calls[-1][0][:2],['cryptsetup','close'])
            for argv,secret in calls:
                self.assertNotIn(self.passphrase,str(argv))
                if argv[:2]==['cryptsetup','open']: self.assertEqual(secret,self.passphrase)

    def test_writable_repair_opens_without_readonly_only_when_requested(self):
        calls,_=self.exercise(writable=True)
        self.assertNotIn('--readonly',next(argv for argv,_ in calls if argv[:2]==['cryptsetup','open']))

    def test_failed_unmount_never_closes_busy_mapper(self):
        calls,state=self.exercise(unmount_failure=True)
        self.assertTrue(state['mapped'])
        self.assertFalse(any(argv[:2]==['cryptsetup','close'] for argv,_ in calls))

    def test_changed_header_refuses_unlock_before_secret_subprocess(self):
        with patch.object(backend.os.path,'lexists',return_value=False), patch.object(backend,'run',return_value='different') as run:
            mapping=recovery.RecoveryLuksRoot('/dev/vda2',self.uuid)
            with self.assertRaisesRegex(backend.InstallError,'changed'):
                mapping.unlock(self.passphrase,False)
            self.assertEqual(run.call_count,1)
            self.assertFalse(mapping.open_attempted)

class RecoveryOperationTests(unittest.TestCase):
    setUp = RecoveryMetadataTests.setUp

    def request(self):
        return dict(disk='/dev/vda', identity='a' * 64, confirm_restore='/dev/vda',
                    installation=recovery.inspect_installation(self.root)['installation'])

    def test_stale_profile_never_reaches_writable_mount(self):
        request = self.request(); request['installation'] = 'b' * 64
        calls = []
        @contextmanager
        def mounted(layout, writable=False):
            calls.append(writable); yield
        with patch.object(recovery, 'ROOT', self.root), patch.object(recovery, 'recovery_lock', return_value=nullcontext()), patch.object(recovery, 'partition_layout', return_value={'root': '/dev/vda2', 'esp': '/dev/vda1'}), patch.object(recovery, 'mounted_root', side_effect=mounted), patch.object(backend, 'run') as run:
            with self.assertRaises(backend.InstallError): recovery.recover(request, True)
            run.assert_not_called()
        self.assertEqual(calls, [False])

    def test_encrypted_stale_generation_never_reopens_writable(self):
        request=self.request()
        request.update(installation='b'*64,encryption_passphrase='Correct Horse 123')
        layout={'root':'/dev/vda2','esp':'/dev/vda1','luks_uuid':'12345678-1234-4234-8234-123456789abc'}
        calls=[]
        @contextmanager
        def mounted(layout,writable=False,passphrase=None):
            calls.append(writable)
            self.assertEqual(passphrase,request['encryption_passphrase'])
            yield
        with patch.object(recovery,'ROOT',self.root), patch.object(recovery,'recovery_lock',return_value=nullcontext()), patch.object(recovery,'partition_layout',return_value=layout), patch.object(recovery,'mounted_root',side_effect=mounted), patch.object(backend,'run') as run:
            with self.assertRaisesRegex(backend.InstallError,'generations changed'):
                recovery.recover(request,True)
            run.assert_not_called()
        self.assertEqual(calls,[False])

    def test_fixed_boot_only_command_and_cleanup_on_failure(self):
        request = self.request()
        mounts = []
        commands = []
        @contextmanager
        def mounted(layout, writable=False):
            mounts.append(('mount', writable))
            try: yield
            finally: mounts.append(('unmount', writable))
        def run(argv):
            commands.append(argv)
            if 'chroot' in argv: raise backend.InstallError('boot repair failed')
        with patch.object(recovery, 'ROOT', self.root), patch.object(recovery, 'recovery_lock', return_value=nullcontext()), patch.object(recovery, 'partition_layout', return_value={'root': '/dev/vda2', 'esp': '/dev/vda1'}) as verify, patch.object(recovery, 'mounted_root', side_effect=mounted), patch.object(backend, 'run', side_effect=run), patch.object(backend, 'emit'):
            with self.assertRaises(backend.InstallError): recovery.recover(request, True)
        self.assertEqual(verify.call_count, 2)
        self.assertEqual(mounts, [('mount', False), ('unmount', False), ('mount', True), ('unmount', True)])
        self.assertEqual(commands[-1], ['timeout', '--signal=TERM', '--kill-after=10s', '300s', 'env', 'NIXOS_INSTALL_BOOTLOADER=1', 'chroot', str(self.root), '/nix/var/nix/profiles/system/bin/switch-to-configuration', 'boot'])
        self.assertIn(['mount', '-t', 'tmpfs', '-o', 'mode=0755,nosuid,nodev', 'tmpfs', str(self.root / 'run')], commands)
        self.assertFalse(any('activate' in argument or 'tmpfiles' in argument or argument.startswith('mkfs') for command in commands for argument in command))
        self.assertEqual(recovery.inspect_installation(self.root)['installation'], request['installation'])

    def test_private_namespace_is_established_before_mount_propagation_change(self):
        calls = []
        with patch.object(recovery.os, 'unshare', side_effect=lambda flags: calls.append(('unshare', flags))), patch.object(backend, 'run', side_effect=lambda argv: calls.append(('run', argv))):
            recovery.private_namespace()
        self.assertEqual(calls, [('unshare', recovery.os.CLONE_NEWNS), ('run', ['mount', '--make-rprivate', '/'])])
        with patch.object(recovery.os, 'unshare', side_effect=OSError('no namespace capability')), patch.object(backend, 'run') as run:
            with self.assertRaises(OSError): recovery.private_namespace()
            run.assert_not_called()


if __name__ == '__main__': unittest.main()
