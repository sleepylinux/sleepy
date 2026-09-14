# Installer network firmware

The UEFI text installer uses the firmware framebuffer (or a virtual GPU), so its
host profile prevents AMD, Intel and NVIDIA GPU modules from loading. The
installed desktop keeps its normal hardware profile and firmware selection.

This package filters the **pinned, already compressed** Nixpkgs linux-firmware
output. It keeps Intel iwlwifi; Qualcomm/Atheros ath6k/9k/10k/11k/12k; Broadcom and
Cypress; Marvell client Wi-Fi; MediaTek mt76/mt79/WIFI; Realtek rtlwifi/rtw88/rtw89;
RSI, TI and Silicon Labs Wi-Fi. Wired groups cover Intel e100/ice, Realtek rtl_nic,
Broadcom bnx2/bnx2x/tigon, Chelsio cxgb3/4, 3Com, AceNIC, Kawasaki and Tehuti.
The host also includes the small ipw2200, rtl8192su and zd1211 packages plus the
wireless regulatory database. Server-switch firmware, GPU, accelerator, audio and
Bluetooth-only families are omitted; this is not universal hardware coverage.

Relative firmware aliases are retained. Out-of-tree links fail the filter;
Nix rejects runtime references to the complete firmware package. Compression is
not repeated. Updating linux-firmware must pass the behavioral tests, required
family checks and broken-link check in the package build.

For linux-firmware 20260810, the built package retains 1,127 files/aliases and has
NAR size 218,872,584 bytes, down from 819,681,744 bytes (73% smaller). These are
package sizes, not a measured final ISO size. Source derivations still need the
complete cached firmware to build the filtered result.

Run `python3 packages/sleepy-installer-firmware/test_filter.py` for the focused
filter tests. Actual package-build and Nix option-matrix evidence is recorded in
`work/evidence/installer-firmware-*` and `installer-options-eval.json`; physical
Wi-Fi/GPU coverage requires hardware testing beyond VM boot.
