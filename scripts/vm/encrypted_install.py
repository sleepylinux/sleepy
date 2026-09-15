"""Visible encrypted-install/boot gates; never pass credentials through guest argv."""
import os
import secrets
import time


def credential(output):
    value = secrets.token_hex(16)
    fd = os.open(output / 'test-disk-credential', os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(fd, 'w') as stream:
        stream.write(value + '\n')
    return value


def select_protection(machine):
    machine.wait_screen('Protect your files', 'installer-protection')
    encrypted = getattr(machine, 'encrypt_install', False)
    if encrypted:
        machine.qmp.keys('down')
        machine.screen('installer-encryption-selected')
    machine.qmp.keys('ret')
    if encrypted:
        for prompt, name in [('Choose your disk passphrase', 'installer-disk-passphrase'),
                             ('Type your disk passphrase again', 'installer-disk-passphrase-confirm')]:
            machine.wait_screen((prompt, 'Your input stays hidden'), name)
            machine.qmp.text(machine.disk_passphrase + '\n')


def normalized(text):
    return ' '.join(text.lower().split())


def prompt_visible(text):
    text = normalized(text)
    return ('please enter passphrase for disk' in text or 'passphrase for /dev/' in text)


def rejection_visible(text):
    text = normalized(text)
    return any(message in text for message in (
        'no key available with this passphrase',
        'failed to activate with specified passphrase',
        'passphrase incorrect',
    ))


def retry_visible(text):
    text = normalized(text)
    prompt = max(text.rfind("please enter passphrase for disk"), text.rfind("passphrase for /dev/"))
    failure = max(text.rfind(message) for message in ("no key available with this passphrase",
        "failed to activate with specified passphrase", "passphrase incorrect"))
    return failure >= 0 and prompt > failure


def wait_unlock_screen(machine, name, rejected=False, retry=False, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        text = machine.screen(name)
        if rejected and rejection_visible(text):
            return
        if not rejected and (retry_visible(text) if retry else prompt_visible(text)):
            return
        if 'welcome back' in normalized(text):
            raise RuntimeError('Encrypted boot reached the greeter without the required unlock gate')
        if machine.process.poll() is not None:
            raise RuntimeError('VM exited during disk unlock')
        time.sleep(2)
    raise RuntimeError('Disk unlock prompt or explicit rejection missing; inspect ' + name + '.png')


def unlock(machine, name):
    if not getattr(machine, 'encrypt_install', False):
        return
    wait_unlock_screen(machine, name + '-disk-unlock-prompt')
    if not getattr(machine, 'wrong_disk_passphrase_checked', False):
        machine.qmp.text('intentionally-wrong-disk-passphrase\n')
        wait_unlock_screen(machine, name + '-disk-wrong-passphrase', rejected=True)
        # A failure message alone is insufficient: wait for the actual retry prompt.
        wait_unlock_screen(machine, name + '-disk-unlock-retry', retry=True)
        machine.wrong_disk_passphrase_checked = True
        machine.encryption_completed.append('wrong-disk-passphrase-rejected')
    machine.qmp.text(machine.disk_passphrase + '\n')


def fixture():
    # Observe the mounted root's kernel device-mapper identity, not saved config text.
    return r'''
root_source=$(findmnt -n -o SOURCE /)
root_device=${root_source%%\[*}
"$python" - "$root_device" <<'ENCRYPTED_ROOT'
import os, pathlib, re, stat, sys
info = os.stat(sys.argv[1])
assert stat.S_ISBLK(info.st_mode), 'root is not a block device'
dm = pathlib.Path(f'/sys/dev/block/{os.major(info.st_rdev)}:{os.minor(info.st_rdev)}/dm/uuid').read_text().strip()
assert re.fullmatch(r'CRYPT-LUKS2-[0-9a-f]{32}-luks-[0-9a-f-]{36}', dm), 'root is not the installed LUKS2 mapping'
ENCRYPTED_ROOT
echo ENCRYPTED_ROOT_ACTIVE_OK
'''
