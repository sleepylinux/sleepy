{pkgs}: let
  firmware = pkgs.compressFirmwareZstd pkgs.linux-firmware;
in
  pkgs.runCommand "sleepy-installer-network-firmware" {
    nativeBuildInputs = [pkgs.python3];
    # Files already have the kernel's supported .zst encoding.
    passthru.compressFirmware = false;
    outputChecks.out.allowedRequisites = ["out"];
    __structuredAttrs = true;
    inherit (pkgs.linux-firmware) meta;
  } ''
    cp ${./filter_firmware.py} filter_firmware.py
    cp ${./test_filter.py} test_filter.py
    python3 test_filter.py
    python3 filter_firmware.py ${firmware}/lib/firmware "$out/lib/firmware"
    # Catch changed upstream layout, accidental GPU inclusion and broken aliases.
    test -d "$out/lib/firmware/intel/iwlwifi"
    test -d "$out/lib/firmware/rtl_nic"
    test -d "$out/lib/firmware/ath10k"
    test ! -e "$out/lib/firmware/amdgpu"
    test ! -e "$out/lib/firmware/nvidia"
    test ! -e "$out/lib/firmware/i915"
    find -L "$out" -type l -print -exec false {} +
  ''
