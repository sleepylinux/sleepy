"""Opt-in real capture VM checks; compose with the existing authenticated audit."""
import time
import shlex

PNG_CHECK = r'''
import hashlib,json,os,pathlib,stat,struct,sys
path=pathlib.Path(sys.argv[1]);uid=int(sys.argv[2]);reply=json.load(sys.stdin)
job=reply['payload']['job'];assert job['state']=='completed'
result=job['result'];assert result['path']==str(path) and result['mimeType']=='image/png'
metadata=path.lstat();assert stat.S_ISREG(metadata.st_mode) and metadata.st_uid==uid and stat.S_IMODE(metadata.st_mode)==0o600
with path.open('rb') as stream:
 assert stream.read(8)==b'\x89PNG\r\n\x1a\n'
 assert stream.read(8)==b'\x00\x00\x00\rIHDR'
 width,height=struct.unpack('>II',stream.read(8))
 stream.seek(-12,2);assert stream.read()==b'\x00\x00\x00\x00IEND\xaeB`\x82'
assert 0<width<=32768 and 0<height<=32768
assert (width,height)==(result['width'],result['height'])
if len(sys.argv)==5:
 expected=tuple(int(int(value)*13000/32767) for value in sys.argv[3:])
 assert abs(width-expected[0])<=3 and abs(height-expected[1])<=3, 'PNG does not match the dragged region'
print('CAPTURE_PNG_INFO '+json.dumps({'width':width,'height':height,'bytes':metadata.st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()},sort_keys=True))
'''


def fixture():
    return r'''
uenv() { runuser -u sleepy -- env HOME=/home/sleepy PATH="/etc/profiles/per-user/sleepy/bin:/home/sleepy/.nix-profile/bin:$PATH" XDG_RUNTIME_DIR=/run/user/$uid DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$uid/bus "$@"; }
capture_request() { uenv timeout 3 sleepyctl capture request "$1"; }
capture_begin() { capture_request "$(jq -cn --arg id "$1" --arg output "$2" '{schemaVersion:1,command:{type:"begin",jobId:$id,outputId:$output}}')"; }
capture_cancel_job() { capture_request "$(jq -cn --arg id "$1" '{schemaVersion:1,command:{type:"cancel",jobId:$id}}')"; }
capture_status() { capture_request "$(jq -cn --arg id "$1" '{schemaVersion:1,command:{type:"status",jobId:$id}}')"; }
capture_wait_state() {
  for attempt in $(seq 1 30); do
    capture_reply=$(capture_status "$1")
    if test "$(printf %s "$capture_reply" | jq -r '.payload.job.state')" = "$2"; then return 0; fi
    # Never retry a terminal failure while hoping it becomes successful.
    case "$(printf %s "$capture_reply" | jq -r '.payload.job.state')" in failed|cancelled|completed) printf '%s\n' "$capture_reply"; return 1;; esac
    sleep 1
  done
  printf '%s\n' "$capture_reply"; return 1
}
capture_visible() { hypr layers -j | jq -e '[.. | objects | select(.namespace? == "sleepy-capture-job")] | length > 0' > /dev/null; }
capture_hidden() { hypr layers -j | jq -e '[.. | objects | select(.namespace? == "sleepy-capture-job")] | length == 0' > /dev/null; }
capture_wait() { for attempt in $(seq 1 30); do if "$@"; then return 0; fi; sleep 1; done; return 1; }
capture_desktop() { test "$(cat /sys/class/tty/tty0/active)" = tty1; }
capture_console() { test "$(cat /sys/class/tty/tty0/active)" = tty2; }
capture_keyboard() { hypr devices -j | jq -e 'any(.keyboards[]; .main==true)' > /dev/null; }
test -S /run/user/$uid/sleepy/capture.sock
test "$(stat -c %a /run/user/$uid/sleepy/capture.sock)" = 600
capture_request '{"schemaVersion":1,"command":{"type":"capabilities"}}' | jq -e '.payload.type=="capabilities" and .payload.screenshot==true and .payload.colorPicker==false'
# Pointer coordinates below target the runner's single 1280x800 scale-1 output.
hypr monitors -j | jq -e 'length==1 and .[0].width==1280 and .[0].height==800 and .[0].scale==1' > /dev/null
capture_output="output:$(hypr monitors -j | jq -er '.[0].name')"
capture_monitor_width=$(hypr monitors -j | jq -er '.[0].width')
capture_monitor_height=$(hypr monitors -j | jq -er '.[0].height')
capture_dir=/run/user/$uid/sleepy/captures
capture_bad=73305412-1111-4111-8111-123456789001
capture_cancel=73305412-1111-4111-8111-123456789002
capture_good=73305412-1111-4111-8111-123456789003
capture_crash=73305412-1111-4111-8111-123456789004
capture_api_cancel=73305412-1111-4111-8111-123456789005
# This fixture executes once per fresh installed VM, never over old job IDs.
for capture_id in "$capture_bad" "$capture_cancel" "$capture_good" "$capture_crash" "$capture_api_cancel"; do test ! -e "$capture_dir/screenshot-$capture_id.png"; done
printf 'CAPTURE_RETURN_TO_DESKTOP\n'
capture_wait capture_desktop
capture_begin "$capture_bad" output:SLEEPY-NONEXISTENT-999 | jq -e '.payload.type=="job"'
capture_wait_state "$capture_bad" failed
printf %s "$capture_reply" | jq -e '.payload.job.diagnostic.code=="outputUnavailable"'
test ! -e "$capture_dir/screenshot-$capture_bad.png"
printf 'CAPTURE_WRONG_OUTPUT_REJECTED_OK\n'
capture_begin "$capture_cancel" "$capture_output" | jq -e '.payload.job.state=="awaitingConsent"'
capture_wait capture_visible
# Exceed the former synchronous desktop mutation deadline. No consent input yet.
sleep 1.1
"$python" - "$uid" "$capture_cancel" <<'CAPTURE_RESPONSIVENESS'
import json,os,subprocess,sys,time
uid,job=sys.argv[1:]
base=['runuser','-u','sleepy','--','env','HOME=/home/sleepy','PATH=/etc/profiles/per-user/sleepy/bin:/home/sleepy/.nix-profile/bin:'+os.environ['PATH'],'XDG_RUNTIME_DIR=/run/user/'+uid,'DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/'+uid+'/bus','sleepyctl']
for args in [['capture','request',json.dumps({'schemaVersion':1,'command':{'type':'status','jobId':job}})],['doctor','--json']]:
 start=time.monotonic();result=subprocess.run(base+args,capture_output=True,text=True,timeout=3);elapsed=time.monotonic()-start
 assert result.returncode==0, result.stderr
 reply=json.loads(result.stdout)
 if args[0]=='capture':assert reply['payload']['job']['state']=='awaitingConsent'
 else:assert 'checks' in reply
 # Existing endpoint deadline is 2s; allow only bounded CLI startup overhead.
 assert elapsed<2.5, 'Capture or desktop query blocked behind human consent'
 print('CAPTURE_RESPONSE_SECONDS '+str(round(elapsed,3)),flush=True)
CAPTURE_RESPONSIVENESS
test "$(locker_state)" = unlocked
printf 'CAPTURE_CONSENT_WAIT_RESPONSIVE_OK\n'
printf 'CAPTURE_CANCEL_READY\n'
capture_wait capture_console
printf 'CAPTURE_CANCEL_CONSOLE_READY\n'
capture_wait capture_desktop
capture_wait capture_keyboard
capture_wait capture_visible
printf 'CAPTURE_CANCEL_RETURNED_READY\n'
capture_wait_state "$capture_cancel" cancelled
capture_wait capture_hidden
test ! -e "$capture_dir/screenshot-$capture_cancel.png"
printf 'CAPTURE_ESCAPE_CANCELLED_NO_PNG_OK\n'
capture_begin "$capture_api_cancel" "$capture_output" | jq -e '.payload.job.state=="awaitingConsent"'
capture_wait capture_visible
capture_cancel_job "$capture_api_cancel" | jq -e '.payload.type=="job"'
capture_wait_state "$capture_api_cancel" cancelled
capture_wait capture_hidden
test ! -e "$capture_dir/screenshot-$capture_api_cancel.png"
printf 'CAPTURE_API_CANCELLED_NO_PNG_OK\n'
capture_begin "$capture_good" "$capture_output" | jq -e '.payload.job.state=="awaitingConsent"'
capture_wait capture_visible
printf 'CAPTURE_SELECT_READY\n'
capture_wait_state "$capture_good" completed
capture_path="$capture_dir/screenshot-$capture_good.png"
printf %s "$capture_reply" | "$python" -c __PNG_CHECK__ "$capture_path" "$uid" "$capture_monitor_width" "$capture_monitor_height"
capture_wait capture_hidden
printf 'CAPTURE_SELECTED_REGION_VALID_PNG_OK\n'
for capture_old_viewer in $(hypr clients -j | jq -r '.[] | select(.class | ascii_downcase | contains("swappy")) | .address'); do
  hypr dispatch closewindow "address:$capture_old_viewer"
done
capture_no_viewer() { hypr clients -j | jq -e 'all(.[]; (.class | ascii_downcase | contains("swappy") | not))' > /dev/null; }
capture_wait capture_no_viewer
hypr dispatch exec "swappy -f $capture_path"
capture_viewer() { hypr clients -j | jq -e 'any(.[]; (.class | ascii_downcase | contains("swappy")) and .mapped)' > /dev/null; }
capture_wait capture_viewer
printf 'CAPTURE_VIEWER_READY\n'
# Host acknowledges the screenshot by returning to the already-authenticated VT.
capture_wait capture_console
printf 'CAPTURE_CRASH_RETURN_TO_DESKTOP\n'
capture_wait capture_desktop
capture_begin "$capture_crash" "$capture_output" | jq -e '.payload.job.state=="awaitingConsent"'
capture_wait capture_visible
capture_daemon=$(usystem show sleepy-session.service -P MainPID)
capture_helper=$("$python" - "$capture_daemon" "$capture_crash" <<'CAPTURE_HELPER_PID'
import pathlib,sys,time
parent,job=sys.argv[1:];wanted=('SLEEPY_CAPTURE_JOB_ID='+job).encode();start=time.monotonic()
while time.monotonic()-start<5:
 for child in pathlib.Path('/proc/'+parent+'/task/'+parent+'/children').read_text().split():
  try:
   if wanted in pathlib.Path('/proc/'+child+'/environ').read_bytes().split(b'\0'):
    print(child);sys.exit(0)
  except FileNotFoundError:pass
 time.sleep(.05)
raise RuntimeError('Could not identify the actual capture helper child')
CAPTURE_HELPER_PID
)
test "$capture_helper" -gt 1
# Kill only the installed user daemon, as the existing crash gate does.
usystem kill --kill-whom=main --signal=KILL sleepy-session.service
capture_restarted() {
  new_capture_daemon=$(usystem show sleepy-session.service -P MainPID)
  test "$new_capture_daemon" -gt 1 && test "$new_capture_daemon" != "$capture_daemon" &&
    usystem is-active --quiet sleepy-session.service && test ! -e "/proc/$capture_helper" &&
    capture_request '{"schemaVersion":1,"command":{"type":"capabilities"}}' | jq -e '.payload.screenshot==true' > /dev/null
}
capture_wait capture_restarted
capture_wait capture_hidden
test ! -e "$capture_dir/screenshot-$capture_crash.png"
capture_status "$capture_crash" | jq -e '.payload.type=="error" and .payload.diagnostic.code=="notFound"'
usystem is-active sleepy-shell.service
printf 'CAPTURE_DAEMON_CRASH_CLEANUP_OK\n'
printf 'CAPTURE_CHECKS_COMPLETE\n'
'''.replace('__PNG_CHECK__', shlex.quote(PNG_CHECK))


def advance(machine, report, sent, stage):
    """Ordered whole-line acknowledgements; safe when recv coalesces stages."""
    steps = [b'CAPTURE_RETURN_TO_DESKTOP', b'CAPTURE_CANCEL_READY',
             b'CAPTURE_CANCEL_CONSOLE_READY', b'CAPTURE_CANCEL_RETURNED_READY',
             b'CAPTURE_SELECT_READY', b'CAPTURE_VIEWER_READY',
             b'CAPTURE_CRASH_RETURN_TO_DESKTOP', b'CAPTURE_CHECKS_COMPLETE']
    for index, marker in enumerate(steps):
        if marker in sent:
            continue
        if marker + b'\n' not in report or (index and steps[index-1] not in sent):
            break
        if index == 0:
            machine.qmp.keys('ctrl', 'alt', 'f1'); machine.qmp.keys('shift')
        elif index == 1:
            machine.wait_screen('Capture requested', f'{stage}-capture-consent-before-vt', timeout=30)
            machine.qmp.keys('ctrl', 'alt', 'f2')
        elif index == 2:
            machine.qmp.keys('ctrl', 'alt', 'f1'); machine.qmp.keys('shift')
        elif index in (3, 4):
            machine.wait_screen('Capture requested', f'{stage}-capture-consent-{index}', timeout=30)
            if index == 3:
                machine.qmp.keys('esc')
            else:
                for x, y, down in [(10000, 10000, True), (23000, 23000, False)]:
                    machine.qmp.call('input-send-event', events=[
                        {'type': 'abs', 'data': {'axis': 'x', 'value': x}},
                        {'type': 'abs', 'data': {'axis': 'y', 'value': y}},
                        {'type': 'btn', 'data': {'button': 'left', 'down': down}},
                    ])
                    time.sleep(.3)
        elif index == 5:
            machine.screen(f'{stage}-capture-result-viewer')
            machine.qmp.keys('ctrl', 'alt', 'f2')
        elif index == 6:
            machine.qmp.keys('ctrl', 'alt', 'f1'); machine.qmp.keys('shift')
        else:
            machine.qmp.keys('ctrl', 'alt', 'f2')
        sent.add(marker)


MARKERS = {
    'CAPTURE_WRONG_OUTPUT_REJECTED_OK': 'capture-wrong-output-rejected',
    'CAPTURE_CONSENT_WAIT_RESPONSIVE_OK': 'capture-consent-wait-responsive',
    'CAPTURE_API_CANCELLED_NO_PNG_OK': 'capture-API-cancel-no-PNG',
    'CAPTURE_ESCAPE_CANCELLED_NO_PNG_OK': 'capture-Escape-cancel-no-PNG',
    'CAPTURE_SELECTED_REGION_VALID_PNG_OK': 'capture-selected-region-valid-PNG',
    'CAPTURE_VIEWER_READY': 'capture-PNG-viewer-window',
    'CAPTURE_DAEMON_CRASH_CLEANUP_OK': 'capture-daemon-crash-helper-cleanup',
}
