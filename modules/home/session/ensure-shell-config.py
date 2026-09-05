#!/usr/bin/env python3
"""Publish fresh shell defaults once; never replace user configuration."""
import json
import os
from pathlib import Path
import secrets
import sys


def initialize(directory, template):
    directory = Path(directory)
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Pin the real parent directory for the entire operation. A symlink cannot
    # redirect publication outside the user's selected configuration directory.
    parent = os.open(directory, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        try:
            os.stat('shell.json', dir_fd=parent, follow_symlinks=False)
            return False
        except FileNotFoundError:
            pass
        content = Path(template).read_bytes()
        json.loads(content)
        temporary = '.shell-init-' + secrets.token_hex(16)
        fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW,
                     0o600, dir_fd=parent)
        try:
            with os.fdopen(fd, 'wb') as stream:
                stream.write(content)
                stream.flush()
                os.fsync(stream.fileno())
            try:
                os.link(temporary, 'shell.json', src_dir_fd=parent,
                        dst_dir_fd=parent, follow_symlinks=False)
            except FileExistsError:
                return False
            return True
        finally:
            os.unlink(temporary, dir_fd=parent)
    finally:
        os.close(parent)


if __name__ == '__main__':
    if len(sys.argv) != 3:
        raise SystemExit('Usage: ensure-shell-config.py DIRECTORY TEMPLATE')
    try:
        initialize(sys.argv[1], sys.argv[2])
    except (OSError, ValueError) as error:
        raise SystemExit(f'Sleepy could not initialize shell configuration: {error}')
