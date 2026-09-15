"""Exercise the real EXIT trap with a non-root, read-only Nix-source copy."""
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


class InstalledSourceCleanupTests(unittest.TestCase):
    @unittest.skipIf(os.geteuid() == 0, 'Permission regression must run as a non-root user')
    def test_failed_build_removes_owned_copy_without_following_symlinks(self):
        script = Path(__file__).with_name('installed-source.sh').resolve()
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / 'source'
            nested = source / 'nested'
            nested.mkdir(parents=True)
            (nested / 'file').write_text('immutable source\n')
            external = root / 'external'
            external.mkdir()
            target = external / 'file'
            target.write_text('external target must remain unchanged\n')
            (source / 'outside').symlink_to(external, target_is_directory=True)
            for path in (source, nested, external):
                path.chmod(0o555)
            fixtures = root / 'fixtures'
            fixtures.mkdir()
            binaries = root / 'bin'
            binaries.mkdir()
            nix = binaries / 'nix'
            nix.write_text('#!/bin/sh\ncase "$1" in\nflake) printf \'{"path":"%s"}\\n\' "$TEST_SOURCE" ;;\n*) exit 42 ;;\nesac\n')
            nix.chmod(0o755)
            try:
                result = subprocess.run(['bash', str(script)], env={
                    **os.environ, 'PATH': str(binaries) + os.pathsep + os.environ['PATH'],
                    'TMPDIR': str(fixtures), 'TEST_SOURCE': str(source),
                }, capture_output=True, text=True)
                self.assertEqual(result.returncode, 42, result.stderr)
                self.assertEqual(list(fixtures.iterdir()), [], result.stderr)
                for path in (source, nested, external):
                    self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o555)
                self.assertEqual(target.read_text(), 'external target must remain unchanged\n')
                self.assertEqual((nested / 'file').read_text(), 'immutable source\n')
            finally:
                # Restore only this test's own directories, without symlink traversal.
                for directory, children, _ in os.walk(root, followlinks=False):
                    Path(directory).chmod(0o700)


if __name__ == '__main__':
    unittest.main()
