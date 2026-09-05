{pkgs, ...}: {
  environment.systemPackages = [(pkgs.callPackage ../../../packages/snug {})];
}
