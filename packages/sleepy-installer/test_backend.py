import copy
import importlib.util
import pathlib
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('backend', pathlib.Path(__file__).with_name('backend.py'))
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


def disk(**changes):
    value = {'path': '/dev/vda', 'type': 'disk', 'size': 40*1024**3, 'ro': False,
             'rm': False, 'maj:min': '252:0', 'model': 'Virtual disk', 'serial': 'abc',
             'wwn': '', 'mountpoints': [None], 'children': []}
    value.update(changes)
    return value


def request():
    return {'disk': '/dev/vda', 'identity': backend.describe_disk(disk(), set())['identity'],
            'confirm_erase': '/dev/vda', 'username': 'alice', 'password': 'sëcret123',
            'hostname': 'sleepy', 'locale': 'en_US.UTF-8', 'keyboard': 'us',
            'timezone': 'UTC', 'options': {}}


class ValidationTests(unittest.TestCase):
    def test_network_failure_is_actionable(self):
        with patch.object(backend.urllib.request, 'urlopen', side_effect=OSError('offline')):
            with self.assertRaisesRegex(backend.InstallError, 'Connect the network'):
                backend.check_network()

    def test_host_install_requires_image_marker(self):
        with patch.object(backend.os, 'geteuid', return_value=0), patch.object(pathlib.Path, 'is_file', return_value=False), patch.object(backend, 'validate_request'):
            with self.assertRaisesRegex(backend.InstallError, 'installer image'):
                backend.install(request())

    def test_signal_interrupt_is_controlled_error(self):
        with self.assertRaisesRegex(backend.InstallError, 'interrupted'):
            backend.interrupted(15, None)

    def test_log_is_private_and_rejects_symlink(self):
        import os
        if os.geteuid() != 0: self.skipTest('root ownership verification requires root')
        with tempfile.TemporaryDirectory() as directory:
            path = pathlib.Path(directory) / 'installer.log'
            with patch.object(backend, 'LOG_PATH', path):
                with backend.open_log() as log: log.write('diagnostic')
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                path.unlink(); path.symlink_to(pathlib.Path(directory) / 'elsewhere')
                with self.assertRaises(OSError): backend.open_log()

    def test_valid_request(self):
        self.assertEqual(backend.validate_request(request())['username'], 'alice')

    def test_injection_and_bad_password_rejected(self):
        for key, value in [('hostname', '${builtins.abort "oops"}'), ('username', 'root'),
                           ('password', 'abc\nroot:hacked'), ('timezone', '../etc/passwd'),
                           ('keyboard', 'us;reboot'), ('confirm_erase', '/dev/vdb')]:
            with self.subTest(key=key):
                data = request(); data[key] = value
                with self.assertRaises(backend.InstallError): backend.validate_request(data)

    def test_unknown_options_and_types_rejected(self):
        for options in [{'shell': 'reboot'}, {'gaming': 'false'}, {'nvidia': 1}]:
            data = request(); data['options'] = options
            with self.assertRaises(backend.InstallError): backend.validate_request(data)

    def test_descendant_mount_and_swap_rejected(self):
        for child in [{'path': '/dev/vda1', 'mountpoints': ['/boot']},
                      {'path': '/dev/vda1', 'mountpoints': ['[SWAP]']},
                      {'path': '/dev/vda1', 'mountpoints': [None], 'children': [{'mountpoints': ['/mnt']}]}]:
            self.assertFalse(backend.describe_disk(disk(children=[child]), set())['eligible'])
        self.assertFalse(backend.describe_disk(disk(), {'/dev/vda'})['eligible'])

    def test_memory_disks_are_never_installation_targets(self):
        for path in ['/dev/zram0', '/dev/ram0']:
            with self.subTest(path=path):
                self.assertFalse(backend.describe_disk(disk(path=path, size=64*1024**3), set())['eligible'])

    def test_readonly_removable_and_small_rejected(self):
        for changes in [{'ro': True}, {'rm': True}, {'size': 1024}, {'type': 'part'}]:
            self.assertFalse(backend.describe_disk(disk(**changes), set())['eligible'])

    def test_same_geometry_reformat_changes_identity(self):
        child = {'path': '/dev/vda1', 'maj:min': '252:1', 'size': 1024**3,
                 'type': 'part', 'uuid': 'old-filesystem', 'partuuid': 'partition-id',
                 'ptuuid': 'table-id', 'fstype': 'btrfs'}
        before = backend.describe_disk(disk(children=[child]), set())
        after = backend.describe_disk(disk(children=[dict(child, uuid='new-filesystem')]), set())
        self.assertNotEqual(before['identity'], after['identity'])
        data = request(); data['identity'] = before['identity']
        with patch.object(backend, 'list_disks', return_value=[after]):
            with self.assertRaises(backend.InstallError): backend.verify_target(data)

    def test_diskseq_changes_identity_for_same_device_name(self):
        with patch.object(backend, 'disk_sequence', return_value='100'):
            before = backend.describe_disk(disk(serial=''), set())
        with patch.object(backend, 'disk_sequence', return_value='101'):
            after = backend.describe_disk(disk(serial=''), set())
        self.assertNotEqual(before['identity'], after['identity'])
        data = request(); data['identity'] = before['identity']
        with patch.object(backend, 'list_disks', return_value=[after]):
            with self.assertRaises(backend.InstallError): backend.verify_target(data)

    def test_changed_identity_rejected_before_commands(self):
        with patch.object(backend, 'list_disks', return_value=[backend.describe_disk(disk(serial='changed'), set())]):
            with self.assertRaises(backend.InstallError): backend.verify_target(request())

    def test_config_has_no_password_or_default_nvidia(self):
        config = backend.render_configuration(request())
        self.assertNotIn(request()['password'], config)
        self.assertNotIn('nvidia', config)
        self.assertIn('systemd-boot.enable = true', config)

    def test_selected_keyboard_keeps_ascii_password_layout_available(self):
        for keyboard in ('us', 'ru', 'de', 'cz'):
            with self.subTest(keyboard=keyboard):
                data = request(); data['keyboard'] = keyboard
                config = backend.render_configuration(data)
                layout = 'us' if keyboard == 'us' else 'us,' + keyboard
                options = '' if keyboard == 'us' else 'grp:alt_shift_toggle'
                self.assertIn('console.keyMap = "us";', config)
                self.assertIn(f'services.xserver.xkb.layout = "{layout}";', config)
                self.assertIn(f'services.xserver.xkb.options = "{options}";', config)

    def test_optional_features_are_explicit(self):
        data = request(); data['options'] = {name: True for name in backend.OPTIONS}
        config = backend.render_configuration(data)
        for token in ['nvidia', 'sleepy.features.gaming.enable', 'sleepy.features.flatpak.enable', 'sleepy.features.development.enable', 'sleepy.features.bluetooth.enable']:
            self.assertIn(token, config)

    def test_command_password_only_stdin(self):
        with patch.object(backend.subprocess, 'Popen') as popen:
            process = popen.return_value.__enter__.return_value
            process.returncode = 1
            process.communicate.return_value = (None, None)
            with self.assertRaises(backend.InstallError) as error:
                backend.run(['chpasswd', '-R', '/mnt/sleepy'], secret='alice:'+request()['password']+'\n')
            self.assertNotIn(request()['password'], str(error.exception))
            self.assertNotIn(request()['password'], str(popen.call_args))
            self.assertEqual(popen.call_args.kwargs['stdout'], backend.subprocess.DEVNULL)
            self.assertEqual(popen.call_args.kwargs['stderr'], backend.subprocess.DEVNULL)
            self.assertEqual(process.communicate.call_args.kwargs['input'], 'alice:'+request()['password']+'\n')

    def test_nonsecret_interruption_kills_group_before_any_leader_reap(self):
        events=[]
        with patch.object(backend.subprocess,'Popen') as popen, patch.object(backend.os,'killpg',side_effect=lambda pid,sig:events.append(('signal',sig))):
            process=popen.return_value.__enter__.return_value
            process.pid=12345
            process.returncode=None
            process.stdout.read1.side_effect=backend.InstallError('interrupted')
            process.wait.side_effect=lambda **kwargs:events.append(('reap',None))
            with patch.object(backend.os,'waitid',return_value=object()):
                with self.assertRaisesRegex(backend.InstallError,'interrupted'):
                    backend.run(['nixos-install','--root','/mnt/sleepy'])
        self.assertLess(events.index(('signal',backend.signal.SIGKILL)),events.index(('reap',None)))

    def test_real_nonsecret_interrupted_child_is_reaped(self):
        import os
        import sys
        observed=[]
        def interrupt_ready(value):
            if value.startswith('OWNED_READY '):
                observed.append(int(value.split()[1]))
                raise backend.InstallError('interrupted after real child readiness')
        with patch.object(backend,'log_output',side_effect=interrupt_ready):
            with self.assertRaisesRegex(backend.InstallError,'real child readiness'):
                backend.run([sys.executable,'-c','import os,time; print("OWNED_READY",os.getpid(),flush=True); time.sleep(60)'])
        self.assertEqual(len(observed),1)
        with self.assertRaises(ChildProcessError): os.waitpid(observed[0],os.WNOHANG)

    def test_real_secret_child_output_is_discarded_even_on_failure(self):
        import contextlib
        import io
        import sys
        output = io.StringIO()
        log = io.StringIO()
        secret = 'Disposable Test Passphrase 123'
        with patch.object(backend,'LOG',log), contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
            with self.assertRaises(backend.InstallError) as error:
                backend.run([sys.executable,'-c','import sys; value=sys.stdin.read(); print(value); print(value,file=sys.stderr); sys.exit(7)'],secret=secret)
        self.assertNotIn(secret,str(error.exception))
        self.assertEqual(output.getvalue(),'')
        self.assertEqual(log.getvalue(),'')

    def test_secret_process_interrupt_stops_group_and_reaps(self):
        with patch.object(backend.subprocess,'Popen') as popen, patch.object(backend.os,'killpg') as kill:
            process = popen.return_value.__enter__.return_value
            process.pid = 12345
            process.communicate.side_effect = backend.InstallError('Installation interrupted')
            with self.assertRaisesRegex(backend.InstallError,'interrupted'):
                backend.run(['cryptsetup','open'],secret='Correct Horse 123')
            self.assertTrue(popen.call_args.kwargs['start_new_session'])
            self.assertEqual(kill.call_args_list[-1].args, (12345,backend.signal.SIGKILL))
            process.wait.assert_called()

    def test_optional_luks_passphrase_is_explicit_and_console_reproducible(self):
        data = request()
        data['encryption'] = False
        backend.validate_request(data)
        data.update(encryption=True, encryption_passphrase='Correct Horse 123')
        backend.validate_request(data)
        for value in ['', 'short', 'x'*129, 'passphrase-ééé', 'passphrase\nmore']:
            with self.subTest(value=value):
                invalid = dict(data, encryption_passphrase=value)
                with self.assertRaises(backend.InstallError): backend.validate_request(invalid)
        for invalid in [dict(data, encryption=False), dict(data, encryption='yes'), dict(data, mapper='/dev/mapper/user')]:
            with self.assertRaises(backend.InstallError): backend.validate_request(invalid)

    def test_luks_configuration_uses_internal_uuid_and_us_initrd(self):
        data = dict(request(), encryption=True, encryption_passphrase='Correct Horse 123')
        uuid = '12345678-1234-4234-8234-123456789abc'
        config = backend.render_configuration(data, luks_uuid=uuid)
        self.assertIn('/dev/disk/by-uuid/' + uuid, config)
        self.assertIn('console.keyMap = "us";', config)
        self.assertNotIn(data['encryption_passphrase'], config)
        self.assertNotIn('luks.devices', backend.render_configuration(request()))
        with self.assertRaises(backend.InstallError): backend.render_configuration(data, luks_uuid='../evil')


class EncryptedMappingTests(unittest.TestCase):
    def test_close_rejects_changed_or_preexisting_mapping(self):
        with patch.object(backend.os.path,'lexists',return_value=True):
            with self.assertRaisesRegex(backend.InstallError,'already exists'):
                backend.LuksRoot('/dev/vda2')
        with patch.object(backend.os.path,'lexists',return_value=False):
            mapping=backend.LuksRoot('/dev/vda2')
        mapping.open_attempted=True
        with patch.object(backend.os.path,'lexists',return_value=True), patch.object(mapping,'owned',return_value=False), patch.object(backend,'run') as run:
            with self.assertRaisesRegex(backend.InstallError,'changed'):
                mapping.close()
            run.assert_not_called()

    def test_interruption_after_open_can_close_only_verified_own_mapper(self):
        with patch.object(backend.os.path,'lexists',return_value=False):
            mapping=backend.LuksRoot('/dev/vda2')
            def command(argv, secret=None):
                if argv[0]=='blkid': return mapping.uuid+'\n'
                if argv[:2]==['cryptsetup','open']: raise backend.InstallError('interrupted after open')
                return ''
            with patch.object(backend,'run',side_effect=command):
                with self.assertRaisesRegex(backend.InstallError,'interrupted'):
                    mapping.create('Correct Horse 123')
        self.assertTrue(mapping.open_attempted)
        with patch.object(backend.os.path,'lexists',return_value=True), patch.object(mapping,'owned',return_value=True), patch.object(backend,'run') as run:
            mapping.close()
            run.assert_called_once_with(['cryptsetup','close',mapping.name])
        self.assertFalse(mapping.open_attempted)

    def test_wrong_luks_uuid_never_opens_mapping(self):
        with patch.object(backend.os.path,'lexists',return_value=False), patch.object(backend,'run',return_value='wrong') as run:
            mapping=backend.LuksRoot('/dev/vda2')
            with self.assertRaisesRegex(backend.InstallError,'UUID changed'):
                mapping.create('Correct Horse 123')
            self.assertFalse(mapping.open_attempted)
            self.assertFalse(any(call.args[0][:2]==['cryptsetup','open'] for call in run.call_args_list))

    def test_owned_mapping_requires_exact_kernel_dm_uuid(self):
        from types import SimpleNamespace
        with patch.object(backend.os.path,'lexists',return_value=False): mapping=backend.LuksRoot('/dev/vda2')
        expected='CRYPT-LUKS2-'+mapping.uuid.replace('-','')+'-'+mapping.name
        with patch.object(backend.os,'stat',return_value=SimpleNamespace(st_mode=backend.stat.S_IFBLK,st_rdev=backend.os.makedev(253,3))):
            for value,valid in [(expected,True),(expected+'changed',False),('CRYPT-LUKS2-foreign',False)]:
                with patch.object(pathlib.Path,'read_text',return_value=value):
                    self.assertEqual(mapping.owned(),valid)

class InstallationSequenceTests(unittest.TestCase):
    def exercise_install(self, fail_command=None, offline=False, invalid_config=False, invalid_target=False, encrypted=False):
        from contextlib import ExitStack
        calls = []
        with tempfile.TemporaryDirectory() as temp, ExitStack() as stack:
            root = pathlib.Path(temp) / 'target'
            source = pathlib.Path(temp) / 'source'
            source.mkdir()
            (source / 'flake.nix').write_text('{}')
            (source / 'flake.lock').write_text('{}')
            original_is_dir = pathlib.Path.is_dir
            original_is_file = pathlib.Path.is_file
            stack.enter_context(patch.object(pathlib.Path, 'is_file', lambda p: True if str(p) == '/etc/sleepy-installer-image' else original_is_file(p)))
            stack.enter_context(patch.object(backend, 'ROOT', root))
            stack.enter_context(patch.dict(backend.os.environ, {'SLEEPY_SOURCE': str(source)}))
            stack.enter_context(patch.object(backend.os, 'geteuid', return_value=0))
            stack.enter_context(patch.object(pathlib.Path, 'is_dir', lambda p: True if str(p) == '/sys/firmware/efi' else original_is_dir(p)))
            mapping = {'open': False}
            stack.enter_context(patch.object(backend.uuid, 'uuid4', return_value='12345678-1234-4234-8234-123456789abc'))
            stack.enter_context(patch.object(backend.LuksRoot, 'owned', return_value=True))
            real_lexists = backend.os.path.lexists
            stack.enter_context(patch.object(backend.os.path, 'lexists', side_effect=lambda p: mapping['open'] if str(p).startswith('/dev/mapper/') else real_lexists(p)))
            claim = {'opens': 0, 'held': False}
            def open_device(path, flags, *args):
                claim['opens'] += 1
                if path == '/dev/vda':
                    self.assertTrue(flags & backend.os.O_EXCL)
                    claim['held'] = True
                return 40 + claim['opens']
            def close_device(fd):
                if fd == 42: claim['held'] = False
            stack.enter_context(patch.object(backend.os, 'open', side_effect=open_device))
            stack.enter_context(patch.object(backend.os, 'close', side_effect=close_device))
            stack.enter_context(patch.object(backend.fcntl, 'flock'))
            stack.enter_context(patch.object(backend.stat, 'S_ISBLK', return_value=True))
            stack.enter_context(patch.object(backend.os, 'fstat', return_value=type('Stat', (), {'st_mode': 0, 'st_rdev': 0})()))
            real_stat = backend.os.stat
            stack.enter_context(patch.object(backend.os, 'stat', side_effect=lambda p, *a, **kw: type('Stat', (), {'st_rdev': 0})() if p == '/dev/vda' else real_stat(p, *a, **kw)))
            verify = stack.enter_context(patch.object(backend, 'verify_target', return_value=backend.describe_disk(disk(), set()), side_effect=backend.InstallError('invalid target') if invalid_target else None))
            stack.enter_context(patch.object(backend, 'list_disks', return_value=[backend.describe_disk(disk(), set())]))
            network = stack.enter_context(patch.object(backend, 'check_network', side_effect=backend.InstallError('offline') if offline else None))
            preflight = stack.enter_context(patch.object(backend, 'preflight_configuration', side_effect=backend.InstallError('invalid configuration') if invalid_config else None))
            stack.enter_context(patch.object(backend, 'write_configuration'))
            stack.enter_context(patch.object(backend, 'emit'))
            def command(argv, secret=None):
                calls.append((argv, secret))
                if argv[0] == 'wipefs':
                    self.assertTrue(claim['held'], '--force requires our verified exclusive device claim')
                    self.assertIn('--force', argv)
                if argv[0] == 'parted': self.assertTrue(claim['held'])
                if argv[0].startswith('mkfs.'): self.assertFalse(claim['held'])
                if argv[:2] == ['cryptsetup', 'open']: mapping['open'] = True
                if argv[:2] == ['cryptsetup', 'close']: mapping['open'] = False
                if argv[0] == fail_command: raise backend.InstallError('simulated command failure')
                if argv[0] == 'blkid': return '12345678-1234-4234-8234-123456789abc\n'
                return ''
            stack.enter_context(patch.object(backend, 'run', side_effect=command))
            data = request()
            if encrypted: data.update(encryption=True, encryption_passphrase='Correct Horse 123')
            if fail_command or offline or invalid_config or invalid_target:
                with self.assertRaises(backend.InstallError): backend.install(data)
            else:
                backend.install(data)
            self.assertEqual(verify.call_count, 1 if offline or invalid_config or invalid_target else 3)
            if invalid_target:
                network.assert_not_called()
                preflight.assert_not_called()
        return calls

    def test_invalid_target_never_starts_network_or_configuration_preflight(self):
        self.assertEqual(self.exercise_install(invalid_target=True), [])

    def test_invalid_config_never_touches_disk(self):
        self.assertEqual(self.exercise_install(invalid_config=True), [])

    def test_offline_install_never_touches_disk(self):
        self.assertEqual(self.exercise_install(offline=True), [])

    def test_real_operation_sequence_and_password_transport(self):
        calls = self.exercise_install()
        commands = [argv[0] for argv, _ in calls]
        self.assertLess(commands.index('wipefs'), commands.index('mkfs.btrfs'))
        self.assertLess(commands.index('nixos-install'), commands.index('chpasswd'))
        lock = next((argv for argv, _ in calls if argv[:3] == ['nix', 'flake', 'lock']), None)
        self.assertIsNotNone(lock, 'Target flake must be locked before nixos-install resolves its NAR hash')
        self.assertLess(commands.index('nix'), commands.index('nixos-install'))
        self.assertEqual(commands[-1], 'umount')
        for argv, secret in calls:
            self.assertNotIn(request()['password'], str(argv))
            self.assertEqual(secret is not None, argv[0] == 'chpasswd')
        self.assertIn('--no-root-passwd', next(argv for argv, _ in calls if argv[0] == 'nixos-install'))

    def test_failed_install_unmounts_and_does_not_set_password(self):
        calls = self.exercise_install('nixos-install')
        self.assertEqual(calls[-1][0][0], 'umount')
        self.assertNotIn('chpasswd', [argv[0] for argv, _ in calls])


    def test_encrypted_install_formats_mapper_and_closes_after_unmount(self):
        calls = self.exercise_install(encrypted=True)
        argv = [call[0] for call in calls]
        format_index = next(i for i,a in enumerate(argv) if a[:2] == ['cryptsetup','luksFormat'])
        open_index = next(i for i,a in enumerate(argv) if a[:2] == ['cryptsetup','open'])
        btrfs_index = next(i for i,a in enumerate(argv) if a[0]=='mkfs.btrfs')
        self.assertLess(format_index,open_index)
        self.assertLess(open_index,btrfs_index)
        self.assertEqual(argv[btrfs_index][-1], '/dev/mapper/luks-12345678-1234-4234-8234-123456789abc')
        self.assertEqual(argv[-2][0], 'umount')
        self.assertEqual(argv[-1][:2], ['cryptsetup','close'])
        for args,secret in calls:
            self.assertNotIn('Correct Horse 123', str(args))
            if args[:2] in [['cryptsetup','luksFormat'],['cryptsetup','open']]:
                self.assertEqual(secret,'Correct Horse 123')
                self.assertIn('--key-file',args)

    def test_encrypted_install_failure_unmounts_before_closing(self):
        calls = self.exercise_install('nixos-install', encrypted=True)
        self.assertEqual(calls[-2][0][0], 'umount')
        self.assertEqual(calls[-1][0][:2], ['cryptsetup','close'])

    def test_encrypted_unmount_failure_never_attempts_mapper_close(self):
        calls = self.exercise_install('umount', encrypted=True)
        self.assertFalse(any(args[:2] == ['cryptsetup','close'] for args,_ in calls))

    def test_encrypted_invalid_target_keeps_all_disk_commands_unexecuted(self):
        self.assertEqual(self.exercise_install(invalid_target=True,encrypted=True),[])

if __name__ == '__main__': unittest.main()
