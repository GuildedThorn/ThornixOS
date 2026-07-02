{ config, inputs, ... }:
{
  flake.nixosConfigurations.proxmox-guest = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = { inherit inputs; };
    modules = [
      config.nixos.modules.base
      config.nixos.modules.home-manager-base
      config.nixos.modules.thorn-user

      config.nixos.modules."desktop-xfce-i3"

      config.nixos.modules."services-audio"
      config.nixos.modules."services-clamav"
      # config.nixos.modules."services-ssh"

      config.nixos.modules."thorn-glance"

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      ../../hosts/proxmox-guest/networking.nix
      ../../hosts/proxmox-guest/hardware-configuration.nix

      { home-manager.users.thorn = import ../../hosts/proxmox-guest/home.nix; }

      (
        { ... }:
        {
          security.pki.certificates = [
            (builtins.readFile ../../certs/proxmox.guildedthorn.arpa.crt)
          ];

          boot.loader.grub.devices = [ "nodev" ];
          services.qemuGuest.enable = true;

          boot.growPartition = true;
        }
      )
    ];
  };
}
