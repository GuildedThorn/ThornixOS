{ config, inputs, ... }:
{
  flake.nixosConfigurations.proxmox-websites = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-clamav
      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/websites/hardware-configuration.nix"
      "${inputs.self}/hosts/websites/disko.nix"
      "${inputs.self}/hosts/websites/networking.nix"

      (
        { ... }:
        {
          boot.loader.grub.devices = [ "nodev" ];
          services.qemuGuest.enable = true;

          boot.growPartition = true;
        }
      )
    ];
  };
}
