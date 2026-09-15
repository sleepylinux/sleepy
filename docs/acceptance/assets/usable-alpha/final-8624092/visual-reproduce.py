"""Real QMP/desktop Fastfetch supplement; only a private qcow2 overlay is writable."""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / 'work/vm-final-862-to-d408'
OUT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT / 'scripts/vm'))
spec = importlib.util.spec_from_file_location('sleepy_runner', ROOT / 'scripts/vm/installable-alpha.py')
runner = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runner)


def disk_active():
    for process in Path('/proc').iterdir():
        if not process.name.isdigit():
            continue
        try:
            if 'qemu-system' not in (process / 'comm').read_text():
                continue
            if str(BASE / 'installed.qcow2').encode() in (process / 'cmdline').read_bytes():
                return True
        except OSError:
            continue
    return False


def main():
    result_path = BASE / 'result.json'
    if not result_path.is_file():
        raise SystemExit('Base acceptance has not finished; do not boot')
    baseline = json.loads(result_path.read_text())
    if baseline.get('status') != 'passed' or disk_active():
        raise SystemExit('Require base PASS and stopped original QEMU; do not boot')
    disk = BASE / 'installed.qcow2'
    before = disk.stat()
    firmware_digest = hashlib.sha256((BASE / 'OVMF_VARS.fd').read_bytes()).hexdigest()
    subprocess.run(['qemu-img', 'create', '-f', 'qcow2', '-F', 'qcow2', '-b', str(disk), str(OUT / 'installed.qcow2')], check=True)
    shutil.copy2(BASE / 'OVMF_VARS.fd', OUT / 'OVMF_VARS.fd')
    password = (BASE / 'test-credential').read_text().strip()
    machine = runner.Machine(OUT, Path('/usr/share/edk2/x64/OVMF_CODE.4m.fd'), 6144, 'kvm')
    machine.daily_usability = True
    report = {'kind': 'real-desktop-visual-supplement', 'status': 'running',
              'base_result': str(result_path), 'base_result_sha256': hashlib.sha256(result_path.read_bytes()).hexdigest(),
              'base_image_source_revision': baseline.get('image_source_revision'),
              'base_candidate_revision': baseline.get('candidate_revision'),
              'runner_revision': subprocess.check_output(['git', '-C', str(ROOT), 'rev-parse', 'HEAD'], text=True).strip(),
              'script_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              'guest_memory_mib': 6144, 'guest_configuration_patched': False,
              'fixture_values': False, 'base_disk': str(disk)}
    try:
        machine.boot('visual')
        machine.qmp.call('set_link', name='nic0', up=False)
        runner.login_desktop(machine, password, 'visual')
        machine.qmp.keys('meta_l', 'd')
        time.sleep(2)
        machine.qmp.text('thunar')
        time.sleep(2)
        machine.screen('visual-launcher-thunar')
        # Actual launcher list: Preferences first, File Manager second.
        machine.qmp.keys('down')
        machine.qmp.keys('ret')
        machine.wait_screen('Bookmarks', 'visual-filemanager', timeout=45)
        machine.qmp.keys('meta_l', 'ret')
        time.sleep(3)
        machine.screen('visual-applications')
        machine.qmp.keys('meta_l', 'f')
        time.sleep(2)
        machine.qmp.text('fastfetch\n')
        text = machine.wait_screen(('Disk', 'btrfs', 'Memory'), 'fastfetch-1280', timeout=45)
        from PIL import Image
        with Image.open(OUT / 'fastfetch-1280.png') as image:
            report['screenshot_size'] = list(image.size)
            assert image.width == 1280, 'Screenshot is not actual 1280px desktop'
        report['ocr_disk_and_btrfs_visible'] = True
        machine.qmp.call('system_powerdown')
        machine.process.wait(timeout=120)
        report['status'] = 'captured-pending-human-visual-review'
    except Exception as error:
        report['status'] = 'failed'
        report['error'] = str(error)
        if machine.process is not None and machine.process.poll() is None:
            machine.screen('visual-failure')
        raise
    finally:
        password = None
        machine.stop()
        after = disk.stat()
        report['base_disk_stat_unchanged'] = (before.st_size, before.st_mtime_ns, before.st_ctime_ns) == (after.st_size, after.st_mtime_ns, after.st_ctime_ns)
        report['base_nvram_sha256_unchanged'] = firmware_digest == hashlib.sha256((BASE / 'OVMF_VARS.fd').read_bytes()).hexdigest()
        report['qemu_stopped'] = machine.process is None
        (OUT / 'provenance.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
