{
  inputs,
  primaryUser,
  ...
}: {
  imports = [../modules/nixos];

  nixpkgs.overlays = [inputs.self.overlays.default];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.${primaryUser} = {pkgs, ...}: {
      imports = [../modules/home];

      home.stateVersion = "26.05";

      sleepy = {
        enable = true;
        inherit primaryUser;
        brandingPackage = pkgs.sleepy-branding;
        shellPackage = pkgs.sleepy-shell;
      };
    };
  };
}
