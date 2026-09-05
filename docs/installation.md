# Installing Sleepy on your own machine

Sleepy follows its rolling `main` branch and the Nixpkgs unstable revision
recorded in Sleepy's lock file. Your machine has a separate host flake and lock;
updates advance the Sleepy input as a unit. This guide is the manual fallback
for the bootable installer, and also explains the configuration it produces.
The initial host template targets x86_64 PCs. Broad driver support is not a
claim that every laptop, GPU, suspend path or firmware combination was tested.

## Bootable TUI installer

Build from this repository:

```sh
nix build .#iso
ls result/iso/
```

Write the resulting ISO to a USB drive using an image-writing application,
carefully selecting the USB device. Boot it in UEFI or legacy BIOS mode.
The first console launches Sleepy onboarding automatically. Another TTY provides
a recovery shell; `nmtui` configures networking and `sleepy-install` restarts the
installer. To preview safely from a terminal, run `sleepy-install --demo`.

The onboarding flow covers network setup, a stable disk identity, boot mode,
host/user names, timezone, keyboard, graphics drivers, Development/Games/Apps
categories, masked password entry and final confirmation. NVIDIA users can
choose open or proprietary kernel modules and supported detected PRIME offload
setups. The generated configuration records the choices; the installer does
not infer that every GPU generation supports the same driver.

The automated storage path currently erases one whole disk and creates a GPT
partition table, ext4 root and a boot partition. It requires an unmounted disk
of at least 32 GiB with serial/WWN identity. Mounted disks and the live media
are excluded. There is no automated dual boot, encryption or swap configuration;
use the manual path below for custom storage. The review screen states these
limits before requiring `ERASE /dev/…` and checking disk identity again.

The ISO is an online installer: it bundles the exact Sleepy source and tools,
not every optional application. Selected packages are downloaded or built during
installation. Keep the machine connected to power and the network. Root login
is locked on the installed system; the chosen normal user authenticates sudo.
The installed source/lock and recovery tools are retained; a failed installation
must be investigated before attempting another destructive operation.

## Prepare the target

Back up your data and boot a current NixOS installation image with network
access. Identify disks using `lsblk -f`. Decide explicitly which existing
partitions to retain, resize or replace, and whether to use encryption or swap.
Partitioning and formatting destroy data on the selected partitions; this guide
does not choose a disk or issue a formatting command for you.

Follow the [official manual installation procedure](https://nixos.org/manual/nixos/stable/#sec-installation-manual)
for your chosen layout. Mount the target root at `/mnt`, and any separate boot,
home or encrypted volumes beneath it. The template assumes UEFI with an EFI
system partition mounted at `/mnt/boot`; BIOS requires your own GRUB bootloader
configuration instead. Secure Boot needs additional setup outside this template.

## Create the machine's configuration

From a root shell in the live environment, after mounting the target:

```sh
nixos-generate-config --root /mnt
mv /mnt/etc/nixos/configuration.nix /mnt/etc/nixos/configuration.nix.generated
cd /mnt/etc/nixos
nix --extra-experimental-features 'nix-command flakes' flake init -t github:sleepylinux/sleepy#host
```

The generated configuration is preserved as `configuration.nix.generated`.
Keep the generated `hardware-configuration.nix`: it contains
**your** filesystems and hardware, rather than the developer VM's UUIDs.
Use `configuration.nix.generated` to review the bootloader and other choices
made by the generator, then incorporate relevant settings in the template.

Edit `configuration.nix`: choose your username (replace `alice`), timezone,
keyboard, GPU configuration and bootloader. If changing the output name
`nixosConfigurations.sleepy` in `flake.nix`, also change `host` in the Snug JSON.
`system.stateVersion` and `home.stateVersion` describe initial compatibility;
keep these values on subsequent rolling upgrades. Never put plaintext passwords
or password hashes directly in a flake: its source is copied into the Nix store.

```sh
chown -R root:root /mnt/etc/nixos
chmod -R go-w /mnt/etc/nixos
nix --extra-experimental-features 'nix-command flakes' flake lock /mnt/etc/nixos
nixos-install --flake /mnt/etc/nixos#sleepy
nixos-enter --root /mnt -c 'passwd alice'
```

Replace `alice` in the final command with your selected user. `nixos-install`
prompts for the root password; set the normal-user password separately before
rebooting. The template keeps mutable users so this password persists across
rebuilds. For declarative credentials, configure `hashedPasswordFile` pointing
to a protected file on the target filesystem, provision it before installation,
and follow the [NixOS user-management documentation](https://nixos.org/manual/nixos/stable/#sec-user-management).
Verify the installation succeeded and both passwords are set, then reboot into
the installed disk.

Keep `/etc/nixos` and its parent directories root owned and not writable by
other users. Keep the source writable by root (not a `/nix/store` symlink).
Use `sudoedit /etc/nixos/configuration.nix` for changes. If you use Git here,
track all Nix source files and the lock before building; omit secrets.

## Intel, AMD and NVIDIA

`auto` leaves GPU discovery to Linux and Mesa. It does not silently install the
NVIDIA proprietary stack. Intel and AMD can normally use this default:

```nix
sleepy.hardware.gpu = "auto"; # or "intel", "amd"
sleepy.hardware.cpu = "auto"; # or "intel", "amd"
```

On x86, CPU auto includes both vendors' microcode; only applicable microcode
loads at boot. Generated hardware settings take precedence over these defaults.
Redistributable firmware is enabled by default. Wi-Fi, unusual storage, ARM
boards and vendor-specific laptop quirks may require further host modules.

For a supported discrete NVIDIA GPU:

```nix
sleepy.hardware.gpu = "nvidia";
sleepy.hardware.nvidia.open = false; # proprietary kernel modules
```

For supported GPUs using NVIDIA's open kernel modules, set `open = true`.
Both choices use NVIDIA userspace components and permit unfree Nixpkgs packages.
Open modules support Turing and newer hardware, with additional limitations
listed by [NVIDIA](https://github.com/NVIDIA/open-gpu-kernel-modules#compatible-gpus).
GPU generations are not interchangeable: older cards may require a legacy
driver branch, and newer cards can require the open modules. Inspect the exact
GPU against the supported-products list for the driver in your pinned Nixpkgs.
Select a compatible package explicitly with
`hardware.nvidia.package = config.boot.kernelPackages.nvidiaPackages.<branch>;`
(add `config` to your module arguments). Branch names and compatibility change;
a legacy driver may not support the rolling kernel or the Wayland desktop.
There is no promise that every NVIDIA generation runs this desktop.

For a hybrid Intel/NVIDIA laptop using render offload:

```nix
sleepy.hardware = {
  gpu = "nvidia";
  nvidia = {
    mode = "offload";
    open = true; # only when supported by your GPU and selected driver
    nvidiaBusId = "PCI:1@0:0:0";
    intelBusId = "PCI:0@0:2:0";
  };
};
```

For AMD/NVIDIA, replace `intelBusId` with `amdgpuBusId`. Supply exactly one
integrated GPU and the distinct NVIDIA GPU ID. Find your real addresses with
`lspci -D`; do not copy example IDs blindly. NixOS bus IDs use **decimal**
numbers, while `lspci` reports hexadecimal. For example `0000:0a:00.0` becomes
`PCI:10@0:0:0`. These conventions and offload settings follow the
[upstream NixOS NVIDIA module](https://github.com/NixOS/nixpkgs/blob/nixos-unstable/nixos/modules/hardware/video/nvidia.nix).
Run selected applications with `nvidia-offload application`. External monitor
ports wired to the discrete GPU, suspend and compositor device selection may
need machine-specific work; PRIME X11 sync settings are not a general solution
for Sleepy's Wayland session.

## Updates and recovery

Run `snug --doctor` to inspect setup, `snug -u` for personal packages, and
`snug -u --system` for the rolling OS update. `/etc/snug/system.json` identifies
`/etc/nixos`, output `sleepy` and input `sleepy`. The OS update requires admin
authentication and builds before switching. Preserve the host lock file and
previous system generations. The host's initial lock records precisely what
was installed; do not independently advance every component input.

If a new system boots badly, select a previous NixOS generation in the boot
menu. From a working console use `snug -b --system`, or the native recovery
command `sudo nixos-rebuild switch --rollback`. Personal rollback is `snug -b`.
Avoid garbage-collecting old generations until the current one has passed your
own login, graphics, networking, suspend and peripheral checks.

## Fresh desktop sleep defaults

On first activation, Sleepy creates a private mutable
`$XDG_CONFIG_HOME/sleepy/shell.json` (normally `~/.config/sleepy/shell.json`).
The launcher Sleep action and ten-minute idle action use plain suspend, since
the default installation does not provision hibernation swap and resume.
The three-minute lock and five-minute display-off actions remain enabled.
Existing shell configuration files and symlinks are preserved without changes;
this initialization does not migrate existing users' sleep preferences.
Configure hibernation and resume for your hardware before explicitly choosing
suspend-then-hibernate in your own shell settings.

The online installer limits source builds to one job and one compiler core so
the live environment, Nix evaluation and compilation can share memory. Downloads
and large source builds can take time. This reduces peak usage but does not
guarantee that every selectable package builds on low-memory hardware.

## Resume a failed online build without reformatting

If partitioning and configuration generation already succeeded, retain the
existing filesystem and downloaded store. From a recovery TTY, identify the
installation's root partition using `lsblk -f`, mount it explicitly with
`mount -t ext4 <root-partition> /mnt`, and for UEFI mount its ESP with
`mount -t vfat <efi-partition> /mnt/boot`. Replace the placeholders with the
partitions you identified. Inspect `/mnt/etc/nixos/install-plan.json` and the
host flake before resuming; do not run the whole-disk onboarding again.

Run `nixos-install --root /mnt --flake /mnt/etc/nixos#<hostname>
--no-root-passwd --max-jobs 1 --cores 1` as one command, replacing `<hostname>`
with the recorded output name. After success, set the chosen account's password
with `nixos-enter --root /mnt -c 'passwd <username>'`, replacing `<username>`.
Unmount the ESP first (if mounted), then root, before rebooting. This route
reuses successful downloads/builds and does not rerun partitioning or formatting.

The RU desktop keyboard choice keeps US as the initial layout and adds Russian;
Alt+Shift switches between them. This preserves Latin input for commands and
passwords. Other offered desktop layouts use the selected layout directly.

## Virtual machines

For graphical desktop testing, use VirtIO graphics with 3D acceleration or an
appropriate passed-through GPU, as described in the
[Hyprland VM guidance](https://wiki.hypr.land/getting-started/master-tutorial/)
and [QEMU VirtIO GPU documentation](https://www.qemu.org/docs/master/system/devices/virtio/virtio-gpu.html).
The text installer can boot with a basic virtual VGA device; that does not
establish that the installed Wayland desktop will work correctly on that device.
The acceptance run using QEMU standard VGA encountered renderer/device recovery
failures after VT switching. Keep installer boot evidence separate from desktop
GPU, VT-switch and suspend acceptance.


## Terminal access

`Super+Enter` opens Ghostty. `Super+Shift+Enter` opens Foot, a lightweight
Wayland terminal available on every installation. Use Foot when the GPU cannot
meet Ghostty's OpenGL requirement; the tested virtual renderer exposed OpenGL
4.2 and Ghostty required 4.3. This fallback does not change global graphics
settings or require downloading a terminal after installation.
