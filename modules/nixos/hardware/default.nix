{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.sleepy.hardware;
  hybrid = cfg.gpu == "nvidia" && cfg.nvidia.mode == "offload";
  busId = lib.mkOption {
    type = lib.types.strMatching "(PCI:[0-9]{1,3}(@[0-9]{1,10})?:[0-9]{1,2}:[0-7])?";
    default = "";
    description = "Decimal PCI bus ID (for example PCI:1@0:0:0); empty when unused.";
  };
in {
  options.sleepy.hardware = {
    gpu = lib.mkOption {
      type = lib.types.enum ["auto" "intel" "amd" "nvidia"];
      default = "auto";
      description = "GPU setup. Auto uses kernel detection and Mesa; NVIDIA requires explicit selection.";
    };
    cpu = lib.mkOption {
      type = lib.types.enum ["auto" "intel" "amd"];
      default = "auto";
      description = "CPU microcode vendor; auto includes both vendors on x86.";
    };
    nvidia = {
      open = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Use NVIDIA open kernel modules; requires a supported Turing-or-newer GPU and matching driver.";
      };
      mode = lib.mkOption {
        type = lib.types.enum ["dedicated" "offload"];
        default = "dedicated";
        description = "Dedicated GPU or PRIME render offload with an Intel/AMD integrated GPU.";
      };
      nvidiaBusId = busId;
      intelBusId = busId;
      amdgpuBusId = busId;
    };
  };
  config = lib.mkMerge [
    {
      hardware.graphics.enable = lib.mkDefault true;
      hardware.enableRedistributableFirmware = lib.mkDefault true;
      assertions = [
        {
          assertion = !hybrid || (cfg.nvidia.nvidiaBusId != "" && ((cfg.nvidia.intelBusId != "") != (cfg.nvidia.amdgpuBusId != "")));
          message = "Sleepy NVIDIA offload requires nvidiaBusId and exactly one of intelBusId/amdgpuBusId.";
        }
        {
          assertion = !hybrid || (cfg.nvidia.nvidiaBusId != cfg.nvidia.intelBusId && cfg.nvidia.nvidiaBusId != cfg.nvidia.amdgpuBusId);
          message = "Sleepy NVIDIA and integrated GPU PCI bus IDs must differ.";
        }
        {
          assertion = cfg.nvidia.mode != "offload" || cfg.gpu == "nvidia";
          message = "Sleepy NVIDIA offload requires sleepy.hardware.gpu = nvidia.";
        }
      ];
    }
    (lib.mkIf pkgs.stdenv.hostPlatform.isx86 {
      hardware.cpu.intel.updateMicrocode = lib.mkDefault (cfg.cpu != "amd");
      hardware.cpu.amd.updateMicrocode = lib.mkDefault (cfg.cpu != "intel");
    })
    (lib.mkIf (cfg.gpu == "intel") {
      services.xserver.videoDrivers = lib.mkDefault ["modesetting"];
    })
    (lib.mkIf (cfg.gpu == "amd") {
      boot.initrd.kernelModules = ["amdgpu"];
      services.xserver.videoDrivers = lib.mkDefault ["amdgpu"];
    })
    (lib.mkIf (cfg.gpu == "nvidia") {
      nixpkgs.config.allowUnfree = lib.mkDefault true;
      services.xserver.videoDrivers = ["nvidia"];
      hardware.nvidia = {
        open = lib.mkDefault cfg.nvidia.open;
        modesetting.enable = true;
        prime = lib.mkIf hybrid {
          inherit (cfg.nvidia) nvidiaBusId intelBusId amdgpuBusId;
          offload.enable = true;
          offload.enableOffloadCmd = true;
        };
      };
    })
  ];
}
