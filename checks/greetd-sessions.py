"""Validate the generated login choices and UWSM's real compositor entry parser."""
import configparser
import sys
from pathlib import Path

from uwsm.main import check_entry_basic
from xdg.DesktopEntry import DesktopEntry

sessions = Path(sys.argv[1]) / "share/wayland-sessions"
visible = []
for path in sorted(sessions.glob("*.desktop")):
    entry = configparser.ConfigParser(interpolation=None)
    entry.read(path)
    desktop = entry["Desktop Entry"]
    if not desktop.getboolean("Hidden", fallback=False) and not desktop.getboolean("NoDisplay", fallback=False):
        visible.append(path.name)
assert visible == ["hyprland-uwsm.desktop"], f"Unsafe login choices: {visible}"

raw = DesktopEntry(str(sessions / "hyprland.desktop"))
assert raw.getNoDisplay() and not raw.getHidden()
# NoDisplay hides a choice from ReGreet; it must remain executable by UWSM.
check_entry_basic(raw)
wrapped = DesktopEntry(str(sessions / "hyprland-uwsm.desktop"))
check_entry_basic(wrapped)
assert "uwsm start" in wrapped.getExec()
assert "hyprland.desktop" in wrapped.getExec()
print("Only UWSM is visible; its raw compositor entry remains valid")
