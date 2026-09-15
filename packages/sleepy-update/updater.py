"""Stage an explicitly approved Sleepy source for next boot; never live-switch."""

import argparse
import base64
from contextlib import contextmanager
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import selectors
import signal
import stat
import subprocess
import sys
import time

STORE = Path("/nix/store")
CATALOG = Path("/etc/sleepy/candidates")
CONFIG = Path("/etc/nixos")
STATE = Path("/var/lib/sleepy-update")
PROFILE = Path("/nix/var/nix/profiles/system")
RUNNING = Path("/run/current-system")
SOURCE_METADATA = RUNNING / "etc/sleepy/source.json"
OWNER_UID = 0
ID = re.compile(r"[a-z0-9][a-z0-9._-]{0,63}")
STORE_NAME = re.compile(r"[0123456789abcdfghijklmnpqrsvwxyz]{32}-[A-Za-z0-9+._?=-]+")
LOG = None


class UpdateError(Exception):
    pass


def emit(stage, message, progress=0):
    print(json.dumps(dict(stage=stage, message=message, progress=progress)), flush=True)


def trusted(path, directory=False):
    info = path.lstat()
    if (
        info.st_uid != OWNER_UID
        or info.st_mode & 0o022
        or not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode))
    ):
        raise UpdateError("Untrusted file ownership or permissions: " + str(path))


def store_path(value, system=False):
    if not isinstance(value, str):
        raise UpdateError("Invalid store path")
    path = Path(value)
    if path.parent != STORE or not STORE_NAME.fullmatch(path.name) or path.is_symlink():
        raise UpdateError("Invalid store path")
    trusted(path, True)
    if system:
        if "-nixos-system-" not in path.name:
            raise UpdateError("Not a NixOS system output")
        program = path / "bin/switch-to-configuration"
        if not program.is_file() or not os.access(program, os.X_OK):
            raise UpdateError("Missing system boot program")
    return path


def read_json(path):
    if path.is_symlink():
        resolved = path.resolve(strict=True)
        try:
            relative = resolved.relative_to(STORE)
        except ValueError:
            raise UpdateError(
                "Metadata symlink must point into the Nix store"
            ) from None
        store_path(str(STORE / relative.parts[0]))
        path = resolved
    trusted(path)
    if path.stat().st_size > 16384:
        raise UpdateError("Metadata is too large")
    with path.open("rb") as stream:
        raw = stream.read(16385)
    if len(raw) > 16384:
        raise UpdateError("Metadata is too large")
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise UpdateError("Invalid metadata object")
    return value


def validate_common(value):
    if type(value.get("schema")) is not int or value["schema"] != 1:
        raise UpdateError("Unsupported metadata schema")
    version = value.get("version")
    if (
        not isinstance(version, str)
        or not 1 <= len(version) <= 120
        or not all(c.isprintable() for c in version)
    ):
        raise UpdateError("Invalid version label")
    revision = value.get("revision")
    if revision is not None and (
        not isinstance(revision, str) or not re.fullmatch("[0-9a-f]{40}", revision)
    ):
        raise UpdateError("Invalid source revision")
    digest = value.get("nar_hash")
    try:
        if (
            not isinstance(digest, str)
            or not digest.startswith("sha256-")
            or len(base64.b64decode(digest[7:], validate=True)) != 32
        ):
            raise ValueError()
    except ValueError:
        raise UpdateError("Invalid source NAR hash") from None


def running_source():
    if not SOURCE_METADATA.exists() and not SOURCE_METADATA.is_symlink():
        return ""
    value = read_json(SOURCE_METADATA)
    if set(value) != {"schema", "source_path", "nar_hash", "revision", "version"}:
        raise UpdateError("Invalid running source metadata")
    validate_common(value)
    source = store_path(value["source_path"])
    if not (source / "flake.nix").is_file():
        raise UpdateError("Running source has no flake")
    return str(source)


def candidates():
    if not CATALOG.exists():
        return []
    trusted(CATALOG, True)
    result = []
    with os.scandir(CATALOG) as entries:
        for index, entry in enumerate(entries):
            if index >= 128:
                raise UpdateError("Too many candidate catalog files")
            if not entry.name.endswith(".json"):
                raise UpdateError("Unexpected candidate catalog file")
            value = read_json(CATALOG / entry.name)
            if set(value) != {"schema", "id", "version", "revision", "nar_hash"}:
                raise UpdateError("Invalid candidate fields")
            validate_common(value)
            if (
                not isinstance(value["id"], str)
                or not ID.fullmatch(value["id"])
                or entry.name != value["id"] + ".json"
                or value["revision"] is None
            ):
                raise UpdateError("Invalid candidate identity")
            result.append(value)
    return sorted(result, key=lambda item: item["id"])


def configuration_snapshot():
    """Hash saved files plus link targets; never follow links out of the config."""
    trusted(CONFIG, True)
    digest = hashlib.sha256()
    total = 0
    count = 0
    for directory, dirs, files in os.walk(CONFIG, followlinks=False):
        dirs.sort()
        files.sort()
        for name in dirs + files:
            path = Path(directory) / name
            info = path.lstat()
            count += 1
            if count > 20000:
                raise UpdateError("Saved configuration has too many files")
            digest.update(str(path.relative_to(CONFIG)).encode() + b"\0")
            digest.update(str(info.st_mode).encode() + b"\0")
            if info.st_uid != OWNER_UID or (
                not stat.S_ISLNK(info.st_mode) and info.st_mode & 0o022
            ):
                raise UpdateError(
                    "Untrusted saved configuration ownership or permissions"
                )
            if stat.S_ISLNK(info.st_mode):
                destination = path.resolve(strict=True)
                if not destination.is_relative_to(
                    CONFIG
                ) and not destination.is_relative_to(STORE):
                    raise UpdateError(
                        "Saved configuration link points outside the config or immutable store"
                    )
                digest.update(os.readlink(path).encode())
            elif stat.S_ISREG(info.st_mode):
                total += info.st_size
                if total > 64 * 1024 * 1024:
                    raise UpdateError("Saved configuration exceeds snapshot limit")
                with path.open("rb") as stream:
                    while chunk := stream.read(65536):
                        digest.update(chunk)
            elif not stat.S_ISDIR(info.st_mode):
                raise UpdateError("Unsupported saved configuration entry")
    if not (CONFIG / "flake.nix").is_file():
        raise UpdateError("Saved installed flake is missing")
    return digest.hexdigest()


def profile():
    trusted(PROFILE.parent, True)
    target = os.readlink(PROFILE)
    match = re.fullmatch(r"system-([1-9][0-9]{0,8})-link", Path(target).name)
    if not match or (
        Path(target).is_absolute() and Path(target).parent != PROFILE.parent
    ):
        raise UpdateError("Unsupported system profile link")
    retained = PROFILE.parent / ("system-" + match[1] + "-link")
    if not retained.is_symlink() or PROFILE.resolve() != retained.resolve():
        raise UpdateError("Invalid retained system generation")
    return dict(
        generation=int(match[1]), system=str(store_path(str(retained.resolve()), True))
    )


def write_journal(value):
    temporary = STATE / "transaction.new"
    fd = os.open(
        temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW, 0o600
    )
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", closefd=False) as stream:
            json.dump(value, stream)
            stream.flush()
            os.fsync(fd)
    finally:
        os.close(fd)
    os.replace(temporary, STATE / "transaction.json")
    fd = os.open(STATE, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def status():
    path = STATE / "transaction.json"
    if not path.exists():
        return {"schema": 1, "phase": "idle"}
    # Public status exposes fixed transaction facts, never configuration or logs.
    try:
        journal = read_json(path)
        validate_journal(journal)
        return journal
    except PermissionError:
        raise UpdateError(
            "Transaction status is private; run sudo sleepy-update status"
        ) from None


def validate_journal(journal):
    phases = {
        "preparing",
        "failed",
        "selecting",
        "selected",
        "booting",
        "recovering",
        "recovered",
        "recovery-failed",
        "ready",
    }
    if (
        set(journal) - {"schema", "phase", "candidate", "old", "configuration", "built"}
        or type(journal.get("schema")) is not int
        or journal.get("schema") != 1
        or journal.get("phase") not in phases
    ):
        raise UpdateError("Invalid update journal")
    candidate = journal.get("candidate")
    if not isinstance(candidate, dict) or set(candidate) != {
        "schema",
        "id",
        "version",
        "revision",
        "nar_hash",
    }:
        raise UpdateError("Invalid journal candidate")
    validate_common(candidate)
    if (
        not isinstance(candidate["id"], str)
        or not ID.fullmatch(candidate["id"])
        or candidate["revision"] is None
    ):
        raise UpdateError("Invalid journal candidate identity")
    old = journal.get("old", {})
    if (
        not isinstance(old, dict)
        or set(old) != {"generation", "system"}
        or type(old["generation"]) is not int
        or not 1 <= old["generation"] <= 999999999
    ):
        raise UpdateError("Invalid previous generation in journal")
    store_path(old["system"], True)
    if "built" in journal:
        store_path(journal["built"], True)
    elif journal["phase"] in {
        "selecting",
        "selected",
        "booting",
        "recovering",
        "recovered",
        "recovery-failed",
        "ready",
    }:
        raise UpdateError("Missing built system in pending journal")
    if not isinstance(journal.get("configuration"), str) or not re.fullmatch(
        "[0-9a-f]{64}", journal["configuration"]
    ):
        raise UpdateError("Invalid configuration snapshot")


@contextmanager
def transaction():
    if os.geteuid() != OWNER_UID:
        raise UpdateError("This operation requires root")
    STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
    trusted(STATE, True)
    if STATE.stat().st_mode & 0o077:
        raise UpdateError("Update state directory must be private (0700)")
    fd = os.open(STATE / "lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    try:
        info = os.fstat(fd)
        if (
            info.st_uid != OWNER_UID
            or not stat.S_ISREG(info.st_mode)
            or info.st_mode & 0o077
        ):
            raise UpdateError("Untrusted update lock")
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise UpdateError("Another update operation is running") from None
        yield
    finally:
        os.close(fd)


def run(argv, timeout=1800, capture=True, progress_stage=None):
    """Bounded output and deadline, child process group reaped on interruption."""
    process = subprocess.Popen(
        argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True
    )
    output = bytearray()
    deadline = time.monotonic() + timeout
    heartbeat = time.monotonic()
    completed = False
    try:
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            selector.register(process.stderr, selectors.EVENT_READ)
            while selector.get_map():
                if time.monotonic() > deadline:
                    raise UpdateError("Command timed out; inspect the update log")
                if progress_stage and time.monotonic() - heartbeat >= 10:
                    emit(
                        progress_stage,
                        "Build running; diagnostics in /var/lib/sleepy-update/update.log",
                        30,
                    )
                    heartbeat = time.monotonic()
                for key, _ in selector.select(0.5):
                    chunk = os.read(key.fileobj.fileno(), 65536)
                    if not chunk:
                        selector.unregister(key.fileobj)
                        break
                    if LOG is not None and LOG.tell() < 8 * 1024 * 1024:
                        LOG.write(chunk)
                        LOG.flush()
                    if capture and key.fileobj is process.stdout:
                        output.extend(chunk)
                        if len(output) > 1024 * 1024:
                            raise UpdateError(
                                "Command output exceeded its safety limit"
                            )
            code = process.wait(timeout=max(1, deadline - time.monotonic()))
            if code:
                raise UpdateError(
                    "Command failed ("
                    + str(code)
                    + "); see /var/lib/sleepy-update/update.log"
                )
            completed = True
            return output.decode("utf-8", errors="strict")
    finally:
        if not completed:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                pass
            # A child may have outlived the group leader while holding a pipe.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=5)
        process.stdout.close()
        process.stderr.close()


def rollback(journal):
    old = journal["old"]
    built = journal.get("built")
    current = profile()
    if current["system"] not in {old["system"], built}:
        raise UpdateError("Cannot recover an unrelated current profile")
    retained = PROFILE.parent / f"system-{old['generation']}-link"
    if not retained.is_symlink() or str(retained.resolve()) != old["system"]:
        raise UpdateError("Previous retained generation changed")
    store_path(old["system"], True)
    run(["nix-store", "--check-validity", old["system"]], timeout=30, capture=False)
    journal["phase"] = "recovering"
    write_journal(journal)
    run(
        [
            "nix-env",
            "--profile",
            str(PROFILE),
            "--switch-generation",
            str(old["generation"]),
        ],
        capture=False,
    )
    run(
        [old["system"] + "/bin/switch-to-configuration", "boot"],
        timeout=300,
        capture=False,
    )
    if profile() != old:
        raise UpdateError("Previous generation was not restored")
    journal["phase"] = "recovered"
    write_journal(journal)
    emit("recovered", "Previous generation restored for next boot", 100)


def recover():
    with transaction():
        journal = status()
        if journal["phase"] not in {
            "selecting",
            "selected",
            "booting",
            "recovering",
            "recovery-failed",
        }:
            raise UpdateError("No incomplete selection requires recovery")
        try:
            rollback(journal)
        except Exception as error:
            journal["phase"] = "recovery-failed"
            write_journal(journal)
            raise UpdateError(
                "Automatic recovery failed; retain the log and use installer recovery: "
                + str(error)
            ) from error


def prepare(candidate_id):
    with transaction():
        previous = status()
        phase = previous["phase"]
        if phase in {
            "selecting",
            "selected",
            "booting",
            "recovering",
            "recovery-failed",
        }:
            raise UpdateError("Incomplete update: run sleepy-update recover first")
        if (
            phase == "ready"
            and str(RUNNING.resolve()) != previous["built"]
            and profile() != previous["old"]
        ):
            raise UpdateError(
                "Candidate already selected; reboot or explicitly roll back first"
            )
        candidate = next((c for c in candidates() if c["id"] == candidate_id), None)
        if candidate is None:
            raise UpdateError("Candidate is not in the approved catalog")
        before = configuration_snapshot()
        old = profile()
        journal = dict(
            schema=1,
            phase="preparing",
            candidate=candidate,
            old=old,
            configuration=before,
        )
        write_journal(journal)
        emit("fetch", "Fetching approved immutable source", 10)
        selected = False
        try:
            metadata = json.loads(
                run(
                    [
                        "nix",
                        "flake",
                        "metadata",
                        "--json",
                        "github:sleepylinux/sleepy/" + candidate["revision"],
                    ],
                    timeout=600,
                )
            )
            locked = metadata.get("locked", {})
            if (
                locked.get("rev") != candidate["revision"]
                or locked.get("narHash") != candidate["nar_hash"]
            ):
                raise UpdateError(
                    "Candidate revision or NAR hash does not match catalog"
                )
            source = store_path(metadata["path"])
            if (
                run(["nix", "hash", "path", str(source)]).strip()
                != candidate["nar_hash"]
            ):
                raise UpdateError("Fetched source hash does not match catalog")
            emit("build", "Building candidate with saved installed settings", 30)
            # --out-link retains the exact result against concurrent store GC.
            run(
                [
                    "nix",
                    "build",
                    "--out-link",
                    str(STATE / "built-system"),
                    "--no-write-lock-file",
                    "--override-input",
                    "sleepy",
                    "path:" + str(source),
                    "path:"
                    + str(CONFIG)
                    + "#nixosConfigurations.installed.config.system.build.toplevel",
                ],
                timeout=7200,
                capture=False,
                progress_stage="build",
            )
            link = STATE / "built-system"
            built = store_path(str(link.resolve()), True)
            run(
                ["nix-store", "--check-validity", str(built)], timeout=30, capture=False
            )
            journal["built"] = str(built)
            if configuration_snapshot() != before or profile() != old:
                raise UpdateError(
                    "Saved configuration or system profile changed during build"
                )
            # Revalidate catalog too, so revoked/altered approval never selects.
            if candidate not in candidates():
                raise UpdateError("Candidate catalog changed during build")
            journal["phase"] = "selecting"
            write_journal(journal)
            selected = True
            emit("select", "Selecting exact built system for next boot", 80)
            run(
                ["nix-env", "--profile", str(PROFILE), "--set", str(built)],
                capture=False,
            )
            journal["phase"] = "booting"
            write_journal(journal)
            run(
                [str(built / "bin/switch-to-configuration"), "boot"],
                timeout=300,
                capture=False,
            )
            if profile()["system"] != str(built):
                raise UpdateError("Selected system profile changed")
            journal["phase"] = "ready"
            write_journal(journal)
            emit(
                "ready",
                "Candidate prepared. Reboot to use it; the running desktop is unchanged.",
                100,
            )
        except BaseException as error:
            if selected:
                try:
                    rollback(journal)
                except BaseException as recovery_error:
                    journal["phase"] = "recovery-failed"
                    write_journal(journal)
                    raise UpdateError(
                        "Update failed and automatic recovery failed: "
                        + str(recovery_error)
                    ) from error
            else:
                journal["phase"] = "failed"
                write_journal(journal)
            raise


def interrupted(signum, frame):
    raise UpdateError("Update interrupted")


def main():
    global LOG
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("source")
    sub.add_parser("status")
    sub.add_parser("recover")
    sub.add_parser("candidates").add_argument("--json", action="store_true")
    sub.add_parser("prepare").add_argument("candidate")
    args = parser.parse_args()
    try:
        if args.command == "source":
            print(running_source())
            return 0
        if args.command == "candidates":
            values = candidates()
            if args.json:
                print(json.dumps(values))
            else:
                for value in values:
                    print(
                        value["id"]
                        + "\t"
                        + value["version"]
                        + " ("
                        + value["revision"][:12]
                        + ")"
                    )
            return 0
        if args.command == "status":
            print(json.dumps(status()))
            return 0
        if os.geteuid() != 0:
            raise UpdateError("This operation requires root")
        STATE.mkdir(mode=0o700, parents=True, exist_ok=True)
        trusted(STATE, True)
        log_path = STATE / "update.log"
        if log_path.exists():
            trusted(log_path)
            if log_path.stat().st_size >= 8 * 1024 * 1024:
                os.replace(log_path, STATE / "previous.log")
        fd = os.open(
            log_path, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600
        )
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            os.close(fd)
            raise UpdateError("Invalid log file")
        os.fchmod(fd, 0o600)
        LOG = os.fdopen(fd, "ab")
        signal.signal(signal.SIGINT, interrupted)
        signal.signal(signal.SIGTERM, interrupted)
        if args.command == "prepare":
            prepare(args.candidate)
        else:
            recover()
        return 0
    except (UpdateError, OSError, ValueError, KeyError) as error:
        if args.command in {"prepare", "recover"}:
            emit("error", str(error))
        else:
            print(str(error), file=sys.stderr)
        return 1
    finally:
        if LOG is not None:
            LOG.close()
            LOG = None


if __name__ == "__main__":
    sys.exit(main())
