{ inputs, ... }:
{
  nixos.modules.services-proxmox =
    {
      lib,
      config,
      pkgs,
      ...
    }:

    {

      # The `qm` binary can resolve to the pve-ha-manager wrapper, which does
      # not include cdrkit in PATH when generating cloud-init images.
      environment.systemPackages = [ pkgs.cdrkit ];

      services.openssh.settings.AcceptEnv = lib.mkForce [
        "LANG"
        "LC_*"
      ];

      services.proxmox-ve = {
        enable = true;
      };

      nixpkgs.overlays = [
        inputs.proxmox-nixos.overlays.${config.nixpkgs.system}
      ];
    };
}
