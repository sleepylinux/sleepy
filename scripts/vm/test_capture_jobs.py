"""Capture VM marker/PNG regressions; no fixture claims a compositor capture."""
import unittest
import capture_jobs

class CaptureProtocolTests(unittest.TestCase):
    def test_coalesced_markers_keep_order_and_partial_lines_do_not_act(self):
        actions=[]
        class QMP:
            def keys(self,*keys):actions.append(('keys',keys))
            def call(self,command,**args):actions.append(('call',command,args))
        class Machine:
            qmp=QMP()
            def screen(self,name):actions.append(('screen',name))
            def wait_screen(self,text,name,timeout=30):actions.append(('wait',text,name))
        machine=Machine();sent=set();advance=capture_jobs.advance
        advance(machine,b'CAPTURE_CANCEL_READY\n',sent,'installed')
        self.assertEqual(actions,[])
        markers=[b'CAPTURE_RETURN_TO_DESKTOP',b'CAPTURE_CANCEL_READY',b'CAPTURE_SELECT_READY',b'CAPTURE_VIEWER_READY',b'CAPTURE_CRASH_RETURN_TO_DESKTOP',b'CAPTURE_CHECKS_COMPLETE']
        report=b''
        for marker in markers:
            before=len(actions);advance(machine,report+marker,sent,'installed');self.assertEqual(len(actions),before)
            report+=marker+b'\n';advance(machine,report,sent,'installed');after=len(actions)
            advance(machine,report,sent,'installed');self.assertEqual(len(actions),after)
        self.assertEqual(actions[0],('keys',('ctrl','alt','f1')))
        self.assertEqual([a for a in actions if a==('keys',('esc',))],[('keys',('esc',))])
        self.assertEqual(actions[-1],('keys',('ctrl','alt','f2')))
        calls=[a for a in actions if a[0]=='call'];self.assertEqual(len(calls),2)
        self.assertTrue(calls[0][2]['events'][-1]['data']['down']);self.assertFalse(calls[1][2]['events'][-1]['data']['down'])

    def test_actual_dispatch_gives_capture_final_vt_ownership_after_idle(self):
        import ast
        from pathlib import Path
        source=Path(__file__).with_name('installable-alpha.py');tree=ast.parse(source.read_text())
        functions={node.name:node for node in tree.body if isinstance(node,ast.FunctionDef)}
        loop=next(node for node in ast.walk(functions['guest_report']) if isinstance(node,ast.While) and 'SLEEPY_REPORT_COMPLETE' in ast.unparse(node.test))
        first=next(i for i,node in enumerate(loop.body) if isinstance(node,ast.If) and 'LOCK_RETURN_TO_DESKTOP' in ast.unparse(node.test))
        calls=[]
        class QMP:
            def keys(self,*keys):calls.append(keys)
        class Machine:
            qmp=QMP();daily_usability=True;capture_jobs=True
            def screen(self,name):pass
        namespace={}
        exec(compile(ast.Module(body=[functions[name] for name in ('advance_locked_vt','advance_daily_menu','advance_daily_idle')],type_ignores=[]),str(source),'exec'),namespace)
        namespace.update(machine=Machine(),report=b'REAL_PASSWORD_LOCK_UNLOCK_OK\nDAILY_IDLE_SHELL_STABLE_OK\nCAPTURE_RETURN_TO_DESKTOP\n',
                         daily_sent={'idle-sampling'},lock_desktop_shown=True,lock_graphical_woken=True,
                         idle_lock_input_sent=True,lock_input_sent=True,lock_returned_to_console=False,
                         stage='test',after_reboot=False,capture_jobs=capture_jobs)
        exec(compile(ast.Module(body=loop.body[first:],type_ignores=[]),str(source),'exec'),namespace)
        self.assertEqual(calls,[('ctrl','alt','f2'),('ctrl','alt','f2'),('ctrl','alt','f1'),('shift',)])

    def test_generated_guest_shell_and_python_are_valid(self):
        import subprocess
        script=capture_jobs.fixture();subprocess.run(['bash','-n'],input=script,text=True,check=True)
        for marker in ('CAPTURE_RESPONSIVENESS','CAPTURE_HELPER_PID'):
            code=script.split("<<'"+marker+"'\n")[1].split('\n'+marker)[0];compile(code,marker,'exec')

    def test_guest_api_cancel_serializes_the_exact_job_id(self):
        import subprocess,json
        function=next(line for line in capture_jobs.fixture().splitlines() if line.startswith('capture_cancel_job()'))
        command='capture_request() { printf "%s" "$1"; }\n'+function+'\ncapture_cancel_job "73305412-1111-4111-8111-123456789005"\n'
        result=subprocess.run(['bash'],input=command,text=True,capture_output=True,check=True)
        self.assertEqual(json.loads(result.stdout),{'schemaVersion':1,'command':{'type':'cancel','jobId':'73305412-1111-4111-8111-123456789005'}})

    def test_png_validator_rejects_mismatched_dimensions_and_symlink(self):
        import tempfile, pathlib, struct, zlib, json, subprocess, sys, os
        def chunk(kind,body):return struct.pack('>I',len(body))+kind+body+struct.pack('>I',zlib.crc32(kind+body)&0xffffffff)
        png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',2,3,8,6,0,0,0))+chunk(b'IDAT',zlib.compress((b'\x00'+b'\x80'*8)*3))+chunk(b'IEND',b'')
        with tempfile.TemporaryDirectory() as directory:
            path=pathlib.Path(directory)/'image.png';path.write_bytes(png);path.chmod(0o600)
            reply={'payload':{'job':{'state':'completed','result':{'path':str(path),'mimeType':'image/png','width':2,'height':3}}}}
            def run(value,p,*size):return subprocess.run([sys.executable,'-c',capture_jobs.PNG_CHECK,str(p),str(os.getuid()),*map(str,size)],input=json.dumps(value),text=True,capture_output=True)
            self.assertEqual(run(reply,path).returncode,0)
            self.assertNotEqual(run(reply,path,1280,800).returncode,0)
            reply['payload']['job']['result']['width']=20;self.assertNotEqual(run(reply,path).returncode,0)
            reply['payload']['job']['result']['width']=2;link=pathlib.Path(directory)/'link.png';link.symlink_to(path);reply['payload']['job']['result']['path']=str(link);self.assertNotEqual(run(reply,link).returncode,0)

if __name__=='__main__':unittest.main()
