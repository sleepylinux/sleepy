import importlib.util, sys, pathlib, json, subprocess, traceback
root = pathlib.Path.cwd()
sys.path.insert(0, str(root/'scripts/vm'))
spec=importlib.util.spec_from_file_location('alpha', root/'scripts/vm/installable-alpha.py')
a=importlib.util.module_from_spec(spec); spec.loader.exec_module(a)
original=root/'work/vm-r1'; output=root/'work/vm-r1-recovery-supported'; output.mkdir(exist_ok=True)
for name in ('installed.qcow2','OVMF_VARS.fd'):
    target=output/name
    if not target.exists(): target.symlink_to(original/name)
password=(original/'test-credential').read_text().strip()
m=a.Machine(output,pathlib.Path('/usr/share/edk2/x64/OVMF_CODE.4m.fd'),8192,'kvm')
m.daily_usability=True; m.flatpak_recovery=False; m.keyboard='ru'; m.pause_at_greeter=False
result={'status':'running','kind':'retained-disk-recovery-resume','original_result':'../vm-r1/result.json','runner_source_revision':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'installed_image_source_revision':'229a794618a694ce3b66bc0d95c32976f10f1531','recovery_image_source_revision':'afd713c','completed':[]}
try:
    print('Booting damaged disk, then offline recovery TUI.',flush=True)
    a.boot_recovery.repair(m, root/'work/artifacts/sleepy-recovery-afd713c.iso',a.serial_line,a.SHELL_PROMPT)
    result['completed'] += ['damaged-disk-no-entry-boot','recovery-inspect-cancel-partitions-unchanged','recovery-busy-target-rejected','real-TUI-boot-repair-and-shutdown']
    print('Booting repaired disk offline and authenticating.',flush=True)
    m.boot('offline-reboot');m.qmp.call('set_link',name='nic0',up=False)
    a.login_desktop(m,password,'offline-reboot')
    a.guest_report(m,password,'offline-reboot',after_reboot=True,final=True,recovery_phase='verify')
    result['completed'] += ['offline-password-desktop-login','profile-userdata-config-preserved','daily-usability-after-repair']
    m.qmp.call('system_powerdown');m.process.wait(timeout=120)
    result['completed'].append('clean-final-shutdown');result['status']='passed'
except BaseException as e:
    result['status']='failed';result['error']=str(e);traceback.print_exc()
    if m.process and m.process.poll() is None:
        try:m.screen('failure')
        except Exception:pass
finally:
    m.stop();(output/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps(result,indent=2),flush=True)
