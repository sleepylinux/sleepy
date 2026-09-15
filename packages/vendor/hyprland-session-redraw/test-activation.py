#!/usr/bin/env python3
"""Compile the pinned production activation callback and scheduling guard.

The collaborators record frame requests; no compositor, DRM, or PAM is mocked
into an integration claim. The installed-VM inactive-lock roundtrip remains the
required integration check.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile


def body_after(source, needle):
    start = source.index(needle) + len(needle)
    depth = 1
    for end in range(start, len(source)):
        depth += (source[end] == "{") - (source[end] == "}")
        if depth == 0:
            return source[start:end]
    raise ValueError("unterminated production function")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--expect-broken", action="store_true")
    args = parser.parse_args()
    activation = body_after((args.source / "src/Compositor.cpp").read_text(),
        "m_aqBackend->session->events.changeActive.listenStatic([this] {")
    schedule = body_after((args.source / "src/output/Monitor.cpp").read_text(),
        "void CMonitor::scheduleFrame(Aquamarine::IOutput::scheduleFrameReason reason) {")
    fixture = r'''
#include <cassert>
#include <vector>
namespace Aquamarine { struct IOutput { enum scheduleFrameReason { DAMAGE }; }; }
struct Logger { template<class... T> void log(T...) {} } logger;
namespace Log { enum { DEBUG }; inline auto logger = &::logger; }
struct Session { bool active = false; } session;
struct Backend { Session* session = &::session; bool hasSession() { return true; } } backend;
struct Compositor { Backend* m_aqBackend = &backend; bool m_sessionActive = false; void activate(); } compositor;
auto g_pCompositor = &compositor;
struct Output { int frames = 0; void scheduleFrame(Aquamarine::IOutput::scheduleFrameReason) { ++frames; } } output, disabledOutput;
struct Monitor {
    bool m_enabled = true, m_renderingActive = false, m_pendingFrame = false;
    int m_activeMonitorRule = 1;
    Output* m_output = &output;
    void scheduleFrame(Aquamarine::IOutput::scheduleFrameReason reason = Aquamarine::IOutput::DAMAGE);
} monitor, disabledMonitor;
struct MonitorState { std::vector<Monitor*> monitors() { return {&monitor, &disabledMonitor}; } } monitors;
namespace State { auto monitorState() { return &monitors; } }
struct Anim { void resetTickState() {} } anim;
namespace Animation { auto mgr() { return &anim; } }
struct Rules { bool scheduled = false; void scheduleReload() { scheduled = true; } } rules;
namespace Config { auto monitorRuleMgr() { return &rules; } }
struct Cursor { void syncGsettings() {} } cursor;
namespace Pointer::Cursor { auto mgr() { return &cursor; } }
struct Renderer { void damageMonitor(Monitor* m) { m->scheduleFrame(); } } renderer;
auto g_pHyprRenderer = &renderer;
void Compositor::activate() { ACTIVATION }
void Monitor::scheduleFrame(Aquamarine::IOutput::scheduleFrameReason reason) { SCHEDULE }
int main() {
    disabledMonitor.m_enabled = false;
    disabledMonitor.m_output = &disabledOutput;
    // Lock surfaces can map and commit while the graphical seat is inactive.
    renderer.damageMonitor(&monitor);
    assert(output.frames == 0);
    compositor.activate();
    assert(output.frames == 0); // deactivation never requests a frame
    session.active = true;
    compositor.activate();
    assert(compositor.m_sessionActive && rules.scheduled);
    assert(disabledOutput.frames == 0);
    if (output.frames == 0) return 42; // dropped damage must be restarted on activation
    session.active = false;
    compositor.activate();
    const int frames = output.frames;
    renderer.damageMonitor(&monitor);
    assert(output.frames == frames);
}
'''.replace("ACTIVATION", activation).replace("SCHEDULE", schedule)
    with tempfile.TemporaryDirectory(prefix="sleepy-activation-") as directory:
        source = Path(directory) / "test.cpp"
        binary = Path(directory) / "test"
        source.write_text(fixture)
        subprocess.run(["g++", "-std=c++20", "-Wall", "-Wextra", "-Werror", str(source), "-o", str(binary)], check=True)
        result = subprocess.run([str(binary)], check=False)
    expected = 42 if args.expect_broken else 0
    if result.returncode != expected:
        raise SystemExit(f"activation regression exit {result.returncode}; expected {expected}")
    print("RED: inactive damage has no activation frame" if args.expect_broken else
          "PASS: activation restarts dropped damage; inactive and disabled outputs stay unscheduled")


if __name__ == "__main__":
    main()
