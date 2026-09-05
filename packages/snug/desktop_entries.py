"""Keep a stable, watched application directory for Snug's personal profile."""
from contextlib import contextmanager
import os
from pathlib import Path
import stat
import uuid


class DesktopSyncError(Exception):
    """The profile changed, but its desktop application projection could not refresh."""


def data_root():
    base = Path(os.environ.get('XDG_DATA_HOME') or Path.home() / '.local/share')
    if not base.is_absolute():
        raise DesktopSyncError('XDG_DATA_HOME must be an absolute path.')
    if '..' in base.parts:
        raise DesktopSyncError('XDG_DATA_HOME must not contain parent-directory components.')
    return base / 'snug'


@contextmanager
def _application_directory(root):
    """Walk through directory descriptors so symlink parents cannot redirect writes."""
    descriptor = os.open('/', os.O_RDONLY | os.O_DIRECTORY)
    try:
        for part in (root / 'applications').parts[1:]:
            try:
                os.mkdir(part, mode=0o755, dir_fd=descriptor)
            except FileExistsError:
                pass
            child = os.open(part, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=descriptor)
            os.close(descriptor)
            descriptor = child
        yield descriptor
    finally:
        os.close(descriptor)


def _target(directory, name):
    try:
        info = os.stat(name, dir_fd=directory, follow_symlinks=False)
    except FileNotFoundError:
        return None
    if stat.S_ISLNK(info.st_mode):
        return os.readlink(name, dir_fd=directory)
    return False


def sync(profile: Path):
    """Project desktop files using their original names and logical profile paths.

    Ownership is exact: a managed link points to PROFILE/share/applications/NAME.
    Foreign files and links are never removed or replaced. Replacing our symlinks
    emits directory watcher events even when a Nix profile changes generation but
    retains an application's filename. The caller serializes profile mutations.
    """
    profile = Path(profile)
    if not profile.is_absolute() or '..' in profile.parts:
        raise DesktopSyncError('The Snug profile path must be absolute, without parent-directory components.')
    applications = profile / 'share/applications'
    try:
        if applications.exists() and not applications.is_dir():
            raise DesktopSyncError('The profile applications path is not a directory.')
        desired = {entry.name for entry in applications.iterdir()
                   if entry.name.endswith('.desktop') and entry.is_file()} if applications.is_dir() else set()
        root = data_root()
        with _application_directory(root) as directory:
            # Validate collisions before changing any entries.
            for name in sorted(desired):
                target = _target(directory, name)
                if target is not None and target != str(applications / name):
                    raise DesktopSyncError(f'Desktop refresh would replace an unmanaged entry: {name}')
            for name in sorted(desired):
                target = str(applications / name)
                temporary = '.snug-' + uuid.uuid4().hex + '.tmp'
                try:
                    os.symlink(target, temporary, dir_fd=directory)
                    previous = _target(directory, name)
                    if previous is not None and previous != target:
                        raise DesktopSyncError(f'Desktop entry changed during refresh: {name}')
                    os.replace(temporary, name, src_dir_fd=directory, dst_dir_fd=directory)
                finally:
                    try:
                        os.unlink(temporary, dir_fd=directory)
                    except FileNotFoundError:
                        pass
            for name in os.listdir(directory):
                if name.endswith('.desktop') and name not in desired and _target(directory, name) == str(applications / name):
                    os.unlink(name, dir_fd=directory)
        return root
    except OSError as error:
        raise DesktopSyncError(f'Could not refresh Snug desktop applications: {error.strerror or error}') from error


if __name__ == '__main__':
    import sys
    try:
        sync(Path(sys.argv[1]))
    except (DesktopSyncError, IndexError) as error:
        print(f'snug desktop setup: {error}', file=sys.stderr)
        sys.exit(1)
