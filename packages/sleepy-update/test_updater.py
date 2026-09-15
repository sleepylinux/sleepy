import base64
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import updater as u


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        for key, value in {
            "STORE": self.root / "store",
            "CATALOG": self.root / "catalog",
            "CONFIG": self.root / "config",
            "STATE": self.root / "state",
            "PROFILE": self.root / "profiles/system",
            "RUNNING": self.root / "running",
            "SOURCE_METADATA": self.root / "metadata.json",
        }.items():
            setattr(self, key, value)
            patcher = patch.object(u, key, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        patcher = patch.object(u, "OWNER_UID", os.getuid())
        patcher.start()
        self.addCleanup(patcher.stop)
        for path in [
            self.STORE,
            self.CATALOG,
            self.CONFIG,
            self.STATE,
            self.PROFILE.parent,
        ]:
            path.mkdir(mode=0o700)
        self.old = self.system("a")
        self.new = self.system("b")
        self.source = self.STORE / ("c" * 32 + "-source")
        self.source.mkdir()
        (self.source / "flake.nix").write_text("{}")
        self.select(1, self.old)
        self.RUNNING.symlink_to(self.old)
        (self.CONFIG / "flake.nix").write_text("saved config")
        self.candidate = {
            "schema": 1,
            "id": "alpha-2",
            "version": "0.2",
            "revision": "d" * 40,
            "nar_hash": "sha256-" + base64.b64encode(b"x" * 32).decode(),
        }
        (self.CATALOG / "alpha-2.json").write_text(json.dumps(self.candidate))
        (self.new / "etc/sleepy").mkdir(parents=True)
        (self.new / "etc/sleepy/source.json").write_text(
            json.dumps(
                {
                    "schema": 1,
                    "source_path": str(self.source),
                    "nar_hash": self.candidate["nar_hash"],
                    "revision": None,
                    "version": "0.2",
                }
            )
        )
        self.calls = []
        self.fail = None
        self.mutate = None

    def system(self, char):
        path = self.STORE / (char * 32 + "-nixos-system-sleepy-26.11")
        (path / "bin").mkdir(parents=True)
        (path / "bin/switch-to-configuration").write_text("#!/bin/sh\n")
        (path / "bin/switch-to-configuration").chmod(0o755)
        return path

    def select(self, number, system):
        link = self.PROFILE.parent / f"system-{number}-link"
        if not link.exists():
            link.symlink_to(system)
        self.PROFILE.unlink(missing_ok=True)
        self.PROFILE.symlink_to(link.name)

    def fake_run(self, argv, **kwargs):
        self.calls.append(argv)
        if self.fail and self.fail(argv):
            raise u.UpdateError("injected failure")
        if "metadata" in argv:
            return json.dumps(
                {
                    "path": str(self.source),
                    "locked": {"rev": "d" * 40, "narHash": self.candidate["nar_hash"]},
                }
            )
        if argv[1:3] == ["hash", "path"]:
            return self.candidate["nar_hash"] + "\n"
        if "build" in argv:
            if self.mutate:
                self.mutate()
            link = Path(argv[argv.index("--out-link") + 1])
            link.unlink(missing_ok=True)
            link.symlink_to(self.new)
            return ""
        if "--set" in argv:
            self.select(2, Path(argv[-1]))
        if "--switch-generation" in argv:
            self.select(int(argv[-1]), self.old)
        return ""

    def prepare(self):
        with patch.object(u, "run", side_effect=self.fake_run), patch.object(u, "emit"):
            return u.prepare("alpha-2")

    def test_legacy_and_running_source(self):
        self.assertEqual(u.running_source(), "")
        value = {
            "schema": 1,
            "source_path": str(self.source),
            "nar_hash": self.candidate["nar_hash"],
            "revision": "d" * 40,
            "version": "0.2",
        }
        self.SOURCE_METADATA.write_text(json.dumps(value))
        self.assertEqual(u.running_source(), str(self.source))
        value["source_path"] = "/tmp/untrusted"
        self.SOURCE_METADATA.write_text(json.dumps(value))
        with self.assertRaises(u.UpdateError):
            u.running_source()

    def test_catalog_is_strict_and_trusted(self):
        self.assertEqual(u.candidates()[0]["id"], "alpha-2")
        path = self.CATALOG / "alpha-2.json"
        path.chmod(0o666)
        with self.assertRaises(u.UpdateError):
            u.candidates()
        path.chmod(0o600)
        data = dict(self.candidate, url="https://evil")
        path.write_text(json.dumps(data))
        with self.assertRaises(u.UpdateError):
            u.candidates()

    def test_success_stages_exact_output_without_touching_saved_configuration(self):
        before = u.configuration_snapshot()
        self.prepare()
        self.assertEqual(u.configuration_snapshot(), before)
        self.assertEqual(self.PROFILE.resolve(), self.new)
        self.assertEqual(u.status()["phase"], "ready")
        build = next(c for c in self.calls if "build" in c)
        self.assertIn("--no-write-lock-file", build)
        self.assertIn("path:" + str(self.source), build)
        self.assertIn(
            [str(self.new / "bin/switch-to-configuration"), "boot"], self.calls
        )
        self.assertFalse(any("switch" == word for call in self.calls for word in call))

    def test_wrong_hash_or_build_failure_never_selects(self):
        original_hash = self.candidate["nar_hash"]
        for failure in ["hash", "build"]:
            with self.subTest(failure=failure):
                self.calls.clear()
                self.candidate["nar_hash"] = original_hash
                self.fail = lambda a: "build" in a if failure == "build" else False
                if failure == "hash":
                    self.candidate["nar_hash"] = (
                        "sha256-" + base64.b64encode(b"y" * 32).decode()
                    )
                with self.assertRaises(u.UpdateError):
                    self.prepare()
                self.assertEqual(self.PROFILE.resolve(), self.old)
                self.assertFalse(any("--set" in c for c in self.calls))
                if failure == "build":
                    self.assertTrue(any("build" in c for c in self.calls))

    def test_config_race_and_profile_race_do_not_select(self):
        self.mutate = lambda: (self.CONFIG / "flake.nix").write_text("changed")
        with self.assertRaisesRegex(u.UpdateError, "changed"):
            self.prepare()
        self.assertEqual(self.PROFILE.resolve(), self.old)
        self.mutate = lambda: self.select(3, self.new)
        with self.assertRaisesRegex(u.UpdateError, "changed"):
            self.prepare()
        self.assertFalse(any("--set" in c for c in self.calls))

    def test_boot_failure_restores_retained_generation_and_old_boot(self):
        self.fail = lambda a: a == [
            str(self.new / "bin/switch-to-configuration"),
            "boot",
        ]
        with self.assertRaises(u.UpdateError):
            self.prepare()
        self.assertEqual(self.PROFILE.resolve(), self.old)
        self.assertIn(
            [str(self.old / "bin/switch-to-configuration"), "boot"], self.calls
        )
        self.assertEqual(u.status()["phase"], "recovered")

    def test_recovery_failure_remains_pending_and_is_honest(self):
        self.fail = lambda a: a[-1:] == ["boot"]
        with self.assertRaisesRegex(u.UpdateError, "recovery"):
            self.prepare()
        self.assertEqual(u.status()["phase"], "recovery-failed")
        self.fail = None
        with patch.object(u, "run", side_effect=self.fake_run), patch.object(u, "emit"):
            u.recover()
        self.assertEqual(u.status()["phase"], "recovered")

    def test_ready_requires_reboot_or_explicit_rollback_before_next_prepare(self):
        self.prepare()
        with self.assertRaisesRegex(u.UpdateError, "reboot"):
            self.prepare()
        self.RUNNING.unlink()
        self.RUNNING.symlink_to(self.new)
        self.prepare()

    def test_pending_recovery_rejects_unrelated_profile(self):
        self.prepare()
        journal = u.status()
        journal["phase"] = "booting"
        u.write_journal(journal)
        other = self.system("f")
        self.select(3, other)
        with patch.object(u, "run", side_effect=self.fake_run), patch.object(u, "emit"):
            with self.assertRaisesRegex(u.UpdateError, "unrelated"):
                u.recover()
        self.assertEqual(self.PROFILE.resolve(), other)

    def test_writable_saved_module_and_changed_approval_never_select(self):
        path = self.CONFIG / "module.nix"
        path.write_text("{}")
        path.chmod(0o666)
        with self.assertRaisesRegex(u.UpdateError, "Untrusted"):
            self.prepare()
        self.assertFalse(self.calls)
        path.chmod(0o600)
        self.mutate = lambda: (self.CATALOG / "alpha-2.json").unlink()
        with self.assertRaisesRegex(u.UpdateError, "catalog changed"):
            self.prepare()
        self.assertFalse(any("--set" in call for call in self.calls))

    def test_untrusted_external_config_link_is_rejected(self):
        outside = self.root / "outside.nix"
        outside.write_text("mutable")
        (self.CONFIG / "module.nix").symlink_to(outside)
        with self.assertRaisesRegex(u.UpdateError, "outside"):
            self.prepare()
        self.assertFalse(self.calls)

    def test_malformed_journal_never_executes_a_recovery_path(self):
        self.prepare()
        journal = u.status()
        journal["phase"] = "booting"
        journal["old"]["generation"] = "../../evil"
        u.write_journal(journal)
        self.calls.clear()
        with patch.object(u, "run", side_effect=self.fake_run), patch.object(u, "emit"):
            with self.assertRaises(u.UpdateError):
                u.recover()
        self.assertFalse(self.calls)

    def test_nix_write_text_store_files_support_catalog_and_running_metadata(self):
        # environment.etc.*.text uses a direct regular-file store entry.
        catalog_file = self.STORE / ("f" * 32 + "-candidate.json")
        catalog_file.write_text(json.dumps(self.candidate))
        catalog_file.chmod(0o444)
        catalog_link = self.CATALOG / "alpha-2.json"
        catalog_link.unlink()
        catalog_link.symlink_to(catalog_file)
        self.assertEqual(u.candidates(), [self.candidate])

        metadata_file = self.STORE / ("g" * 32 + "-sleepy-source.json")
        metadata_file.write_text(
            json.dumps(
                {
                    "schema": 1,
                    "source_path": str(self.source),
                    "nar_hash": self.candidate["nar_hash"],
                    "revision": None,
                    "version": "0.2",
                }
            )
        )
        metadata_file.chmod(0o444)
        self.SOURCE_METADATA.symlink_to(metadata_file)
        self.assertEqual(u.running_source(), str(self.source))
        # Accepting metadata files must not weaken source/system validation.
        with self.assertRaises(u.UpdateError):
            u.store_path(str(catalog_file))
        with self.assertRaises(u.UpdateError):
            u.store_path(str(catalog_file), system=True)

    def test_catalog_symlink_into_store_is_supported_but_outside_is_rejected(self):
        path = self.CATALOG / "alpha-2.json"
        path.unlink()
        approved = self.source / "candidate.json"
        approved.write_text(json.dumps(self.candidate))
        path.symlink_to(approved)
        self.assertEqual(u.candidates()[0], self.candidate)
        path.unlink()
        outside = self.root / "candidate.json"
        outside.write_text(json.dumps(self.candidate))
        path.symlink_to(outside)
        with self.assertRaises(u.UpdateError):
            u.candidates()

    def test_orphaned_previous_build_cannot_replace_new_attempt_result(self):
        self.fail = lambda command: "build" in command
        with self.assertRaises(u.UpdateError):
            self.prepare()
        previous = u.status()
        previous["phase"] = "preparing"
        u.write_journal(previous)
        old_command = next(command for command in self.calls if "build" in command)
        old_root = Path(old_command[old_command.index("--out-link") + 1])
        self.fail = None
        original = self.fake_run

        def overlapping(command, **kwargs):
            result = original(command, **kwargs)
            if "build" in command:
                new_root = Path(command[command.index("--out-link") + 1])
                self.assertNotEqual(new_root, old_root)
                old_root.unlink(missing_ok=True)
                old_root.symlink_to(self.old)
            return result

        with patch.object(u, "run", side_effect=overlapping), patch.object(u, "emit"):
            u.prepare("alpha-2")
        self.assertEqual(self.PROFILE.resolve(), self.new)
        self.assertEqual(old_root.resolve(), self.old)

    def test_built_source_attestation_must_match_approved_source(self):
        path = self.new / "etc/sleepy/source.json"
        value = json.loads(path.read_text())
        value["nar_hash"] = "sha256-" + base64.b64encode(b"z" * 32).decode()
        path.write_text(json.dumps(value))
        with self.assertRaisesRegex(u.UpdateError, "Built system source"):
            self.prepare()
        self.assertFalse(any("--set" in command for command in self.calls))

    def test_selection_failure_after_mutation_recovers(self):
        original = self.fake_run

        def runner(argv, **kwargs):
            result = original(argv, **kwargs)
            if "--set" in argv:
                raise u.UpdateError("interrupted after set")
            return result

        with patch.object(u, "run", side_effect=runner), patch.object(u, "emit"):
            with self.assertRaises(u.UpdateError):
                u.prepare("alpha-2")
        self.assertEqual(self.PROFILE.resolve(), self.old)
        self.assertEqual(u.status()["phase"], "recovered")


class ProcessTests(unittest.TestCase):
    def test_timeout_reaps_real_child(self):
        import sys

        with tempfile.TemporaryDirectory() as temporary:
            pidfile = Path(temporary) / "pid"
            command = [
                sys.executable,
                "-c",
                "import os,sys,time;open(sys.argv[1],'w').write(str(os.getpid()));time.sleep(30)",
                str(pidfile),
            ]
            with self.assertRaisesRegex(u.UpdateError, "timed out"):
                u.run(command, timeout=1)
            child = int(pidfile.read_text())
            with self.assertRaises(ProcessLookupError):
                os.kill(child, 0)

    def test_stderr_diagnostics_do_not_corrupt_json_stdout(self):
        import sys

        output = u.run(
            [
                sys.executable,
                "-c",
                "import sys;print('fetching source',file=sys.stderr);print('{}')",
            ]
        )
        self.assertEqual(json.loads(output), {})

    def test_success_and_nonzero_real_commands_preserve_exit_status(self):
        import sys

        self.assertEqual(
            u.run([sys.executable, "-c", "print('metadata')"]), "metadata\n"
        )
        with self.assertRaisesRegex(u.UpdateError, r"failed \(7\)"):
            u.run([sys.executable, "-c", "raise SystemExit(7)"])


if __name__ == "__main__":
    unittest.main()
