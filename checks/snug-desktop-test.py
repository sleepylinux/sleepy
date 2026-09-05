#!/usr/bin/env python3
"""Desktop projection tests use temporary directories; no Nix or desktop needed."""
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location('desktop_entries', Path(__file__).resolve().parents[1] / 'packages/snug/desktop_entries.py')
entries = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entries)


class DesktopEntriesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data = self.root/'data'
        self.profile = self.root/'profile'
        self.apps = self.profile/'share/applications'
        self.projected = self.data/'snug/applications'
        self.environment = patch.dict(os.environ, {'XDG_DATA_HOME': str(self.data)})
        self.environment.start()
        self.addCleanup(self.environment.stop)

    def app(self, name='org.example.App.desktop', text='[Desktop Entry]\nName=Example\n'):
        self.apps.mkdir(parents=True, exist_ok=True)
        path = self.apps/name
        path.write_text(text)
        return path

    def test_first_install_creates_projection_with_original_id(self):
        source = self.app()
        self.assertEqual(entries.sync(self.profile), self.data/'snug')
        link = self.projected/source.name
        self.assertTrue(link.is_symlink())
        self.assertEqual(os.readlink(link), str(source))
        self.assertEqual(link.read_text(), source.read_text())

    def test_precreated_directory_receives_atomic_watcher_updates(self):
        self.projected.mkdir(parents=True)
        source = self.app()
        entries.sync(self.profile)
        with patch.object(entries.os, 'replace', wraps=os.replace) as replace:
            entries.sync(self.profile)
        replace.assert_called_once()
        self.assertEqual(replace.call_args.args[1], source.name)
        self.assertFalse(any(p.name.endswith('.tmp') for p in self.projected.iterdir()))

    def test_update_and_remove_only_owned_entries(self):
        old = self.app('old.desktop')
        entries.sync(self.profile)
        foreign = self.projected/'foreign.desktop'
        foreign.write_text('Keep this file')
        unrelated = self.projected/'unrelated.desktop'
        unrelated.symlink_to('/some/other/profile/share/applications/unrelated.desktop')
        old.unlink()
        new = self.app('new.desktop')
        entries.sync(self.profile)
        self.assertFalse((self.projected/'old.desktop').is_symlink())
        self.assertTrue((self.projected/new.name).is_symlink())
        self.assertEqual(foreign.read_text(), 'Keep this file')
        self.assertEqual(os.readlink(unrelated), '/some/other/profile/share/applications/unrelated.desktop')

    def test_foreign_name_collision_is_preserved_and_reported(self):
        source = self.app()
        self.projected.mkdir(parents=True)
        collision = self.projected/source.name
        for kind in ['file', 'symlink']:
            if kind == 'file':
                collision.write_text('Do not overwrite')
            else:
                collision.symlink_to('/foreign/missing.desktop')
            with self.assertRaises(entries.DesktopSyncError):
                entries.sync(self.profile)
            if kind == 'file':
                self.assertEqual(collision.read_text(), 'Do not overwrite')
            else:
                self.assertEqual(os.readlink(collision), '/foreign/missing.desktop')
            collision.unlink()

    def test_missing_profile_applications_removes_only_owned_links(self):
        source = self.app()
        entries.sync(self.profile)
        source.unlink()
        self.apps.rmdir()
        entries.sync(self.profile)
        self.assertEqual(list(self.projected.iterdir()), [])

    def test_custom_and_default_data_home_and_relative_rejection(self):
        self.app()
        with patch.dict(os.environ, {'XDG_DATA_HOME': str(self.root/'custom data')}):
            entries.sync(self.profile)
            self.assertTrue((self.root/'custom data/snug/applications/org.example.App.desktop').is_symlink())
        with patch.dict(os.environ, {'XDG_DATA_HOME': '', 'HOME': str(self.root/'home')}):
            self.assertEqual(entries.sync(self.profile), self.root/'home/.local/share/snug')
        with patch.dict(os.environ, {'XDG_DATA_HOME': 'relative'}):
            with self.assertRaises(entries.DesktopSyncError):
                entries.sync(self.profile)

    def test_symlink_parents_are_never_followed_or_replaced(self):
        self.app()
        elsewhere = self.root/'elsewhere'
        elsewhere.mkdir()
        for position in ['data', 'snug', 'applications']:
            with self.subTest(position=position):
                data = self.root/position
                data.mkdir(exist_ok=True)
                if position == 'data':
                    link = data/'redirect'
                    base = link
                elif position == 'snug':
                    link = data/'snug'
                    base = data
                else:
                    (data/'snug').mkdir()
                    link = data/'snug/applications'
                    base = data
                link.symlink_to(elsewhere, target_is_directory=True)
                with patch.dict(os.environ, {'XDG_DATA_HOME': str(base)}):
                    with self.assertRaises(entries.DesktopSyncError):
                        entries.sync(self.profile)
                self.assertTrue(link.is_symlink())
                self.assertEqual(list(elsewhere.iterdir()), [])

    def test_nix_generation_symlink_is_kept_logical(self):
        generation = self.root/'generation-1'
        (generation/'share/applications').mkdir(parents=True)
        (generation/'share/applications/game.desktop').write_text('generation one')
        self.profile.symlink_to(generation, target_is_directory=True)
        entries.sync(self.profile)
        generation2 = self.root/'generation-2'
        (generation2/'share/applications').mkdir(parents=True)
        (generation2/'share/applications/game.desktop').write_text('generation two')
        self.profile.unlink()
        self.profile.symlink_to(generation2, target_is_directory=True)
        entries.sync(self.profile)
        self.assertEqual((self.projected/'game.desktop').read_text(), 'generation two')
        self.assertEqual(os.readlink(self.projected/'game.desktop'), str(self.profile/'share/applications/game.desktop'))


if __name__ == '__main__':
    unittest.main()
