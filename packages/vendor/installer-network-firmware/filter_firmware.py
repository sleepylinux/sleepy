"""Copy installer network firmware, retaining internal aliases without store references."""

import os
import shutil
import sys
from pathlib import Path

# Wi-Fi and common Ethernet adapters. Deliberately excludes GPUs, audio,
# accelerators, server-switch images and Bluetooth-only firmware.
FAMILIES = (
    "intel/iwlwifi/", "intel/ice/", "ath6k/", "ath9k_htc/", "ath10k/",
    "ath11k/", "ath12k/", "brcm/", "cypress/", "libertas/", "mwl8k/",
    "mwlwifi/", "rtl_nic/", "rtlwifi/", "rtw88/", "rtw89/", "rsi/",
    "ti-connectivity/", "wfx/", "3com/", "acenic/", "bnx2/", "bnx2x/",
    "cxgb3/", "cxgb4/", "e100/", "kaweth/", "tigon/", "tehuti/",
)


def selected(name):
    return (
        name.startswith(FAMILIES)
        or name.startswith("mrvl/") and not name.startswith("mrvl/prestera/")
        or name.startswith(("mediatek/mt76", "mediatek/mt79", "mediatek/WIFI_"))
        or "/" not in name and name.startswith((
            "iwlwifi-", "iwl-debug-", "ar5523", "carl9170", "htc_", "rt2561",
            "rt2561s", "rt2661", "rt2860", "rt2870", "rt3070", "rt3071",
            "rt3090", "rt3290", "LICENCE", "LICENSE", "WHENCE",
        ))
    )


def copy_network_firmware(source, output):
    source = source.resolve()
    chosen = {p.relative_to(source) for p in source.rglob("*")
              if not p.is_dir() and selected(p.relative_to(source).as_posix())}
    # Aliases moved to vendor directories are still requested by older kernels.
    for alias in source.iterdir():
        if alias.is_symlink():
            target = alias.resolve(strict=True).relative_to(source)
            if target in chosen:
                chosen.add(alias.relative_to(source))
    pending = list(chosen)
    while pending:
        relative = pending.pop()
        path = source / relative
        if path.is_symlink():
            target = path.resolve(strict=True).relative_to(source)
            if target not in chosen:
                chosen.add(target)
                pending.append(target)
    for relative in sorted(chosen):
        path, destination = source / relative, output / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if path.is_symlink():
            target = path.resolve(strict=True).relative_to(source)
            destination.symlink_to(os.path.relpath(output / target, destination.parent))
        else:
            shutil.copyfile(path, destination)
    return len(chosen)


if __name__ == "__main__":
    source, output = map(Path, sys.argv[1:])
    count = copy_network_firmware(source, output)
    if not count:
        raise SystemExit("No network firmware matched the pinned firmware layout")
    print(f"Retained {count} network firmware files and aliases")
