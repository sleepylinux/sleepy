{
  nixpkgs,
  pkgs,
}: let
  evaluate = hardware:
    (nixpkgs.lib.nixosSystem {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [
        ../modules/nixos/hardware
        {
          sleepy.hardware = hardware;
          system.stateVersion = "26.05";
          fileSystems."/" = {
            device = "/dev/test-root";
            fsType = "ext4";
          };
          boot.loader.grub.enable = false;
        }
      ];
    }).config;
  valid = cfg: builtins.all (entry: entry.assertion) cfg.assertions;
  automatic = evaluate {};
  intel = evaluate {
    gpu = "intel";
    cpu = "intel";
  };
  amd = evaluate {
    gpu = "amd";
    cpu = "amd";
  };
  dedicated = evaluate {gpu = "nvidia";};
  openDriver = evaluate {
    gpu = "nvidia";
    nvidia.open = true;
  };
  offload = evaluate {
    gpu = "nvidia";
    nvidia = {
      mode = "offload";
      nvidiaBusId = "PCI:1@0:0:0";
      intelBusId = "PCI:0@0:2:0";
    };
  };
  amdOffload = evaluate {
    gpu = "nvidia";
    nvidia = {
      mode = "offload";
      nvidiaBusId = "PCI:1@0:0:0";
      amdgpuBusId = "PCI:5@0:0:0";
    };
  };
  missing = evaluate {
    gpu = "nvidia";
    nvidia.mode = "offload";
  };
  ambiguous = evaluate {
    gpu = "nvidia";
    nvidia = {
      mode = "offload";
      nvidiaBusId = "PCI:1:0:0";
      intelBusId = "PCI:0:2:0";
      amdgpuBusId = "PCI:5:0:0";
    };
  };
  same = evaluate {
    gpu = "nvidia";
    nvidia = {
      mode = "offload";
      nvidiaBusId = "PCI:1:0:0";
      intelBusId = "PCI:1:0:0";
    };
  };
  wrongGpu = evaluate {
    gpu = "amd";
    nvidia.mode = "offload";
  };
in
  assert builtins.all valid [automatic intel amd dedicated openDriver offload amdOffload];
  assert automatic.hardware.graphics.enable;
  assert !(builtins.elem "nvidia" automatic.services.xserver.videoDrivers);
  assert intel.services.xserver.videoDrivers == ["modesetting"];
  assert amd.services.xserver.videoDrivers == ["amdgpu"];
  assert builtins.elem "amdgpu" amd.boot.initrd.kernelModules;
  assert !dedicated.hardware.nvidia.open;
  assert openDriver.hardware.nvidia.open;
  assert dedicated.hardware.nvidia.modesetting.enable;
  assert offload.hardware.nvidia.prime.offload.enableOffloadCmd;
  assert amdOffload.hardware.nvidia.prime.amdgpuBusId == "PCI:5@0:0:0";
  assert !(valid missing) && !(valid ambiguous) && !(valid same) && !(valid wrongGpu);
  assert (!pkgs.stdenv.hostPlatform.isx86) || (intel.hardware.cpu.intel.updateMicrocode && !intel.hardware.cpu.amd.updateMicrocode && amd.hardware.cpu.amd.updateMicrocode && !amd.hardware.cpu.intel.updateMicrocode);
    pkgs.runCommand "sleepy-hardware-check" {} ''
      touch "$out"
    ''
