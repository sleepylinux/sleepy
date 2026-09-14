#!/usr/bin/env python3
"""Behavioral checks for the installed-VM runner's read-only locker probe."""
import importlib.util
from pathlib import Path
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unittest

spec = importlib.util.spec_from_file_location('alpha_runner', Path(__file__).with_name('installable-alpha.py'))
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


class LockerProbeTests(unittest.TestCase):
    def probe(self, fragments, delay=0.015):
        # Execute the exact Python passed to the installed guest, over a real
        # stream socket. Fake only the peer; no product authentication is used.
        script = runner.lock_fixture('ru').split("-c '", 1)[1].split("' \"/run", 1)[0]
        with tempfile.TemporaryDirectory() as directory:
            path = str(Path(directory) / 'locker.sock')
            requests = []
            with socket.socket(socket.AF_UNIX) as server:
                server.bind(path)
                server.listen(1)
                def respond():
                    with server.accept()[0] as client:
                        requests.append(client.recv(32))
                        for fragment in fragments:
                            time.sleep(delay)
                            try:
                                client.sendall(fragment)
                            except BrokenPipeError:
                                break
                thread = threading.Thread(target=respond)
                thread.start()
                started = time.monotonic()
                result = subprocess.run([sys.executable, '-c', script, path], capture_output=True, text=True, timeout=4)
                elapsed = time.monotonic() - started
                thread.join(timeout=4)
                self.assertFalse(thread.is_alive())
                self.assertEqual(requests, [b'status\n'])
                return result, elapsed

    def test_fragmented_valid_states(self):
        for state in (b'locked\n', b'unlocked\n'):
            with self.subTest(state=state):
                result, _ = self.probe([bytes([byte]) for byte in state])
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, state.decode())

    def test_rejects_missing_newline_oversize_and_unknown_states(self):
        for fragments in ([b'locked'], [b'x' * 32], [b'error\n']):
            with self.subTest(fragments=fragments):
                result, _ = self.probe(fragments)
                self.assertNotEqual(result.returncode, 0)

    def test_slow_fragments_have_one_total_deadline(self):
        result, elapsed = self.probe([b'l', b'o', b'c', b'k'], delay=0.7)
        self.assertNotEqual(result.returncode, 0)
        self.assertLess(elapsed, 2.6)


if __name__ == '__main__':
    unittest.main()
