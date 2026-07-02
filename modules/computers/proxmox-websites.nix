{ config, inputs, ... }:
{
  flake.nixosConfigurations.proxmox-websites = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      config.nixos.modules.base
      config.nixos.modules.home-manager-base
      config.nixos.modules.thorn-user

      config.nixos.modules."services-clamav"
      config.nixos.modules."services-ssh"

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      ../../hosts/proxmox-websites/hardware-configuration.nix
      ../../hosts/proxmox-websites/disko.nix
      ../../hosts/proxmox-websites/networking.nix

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
