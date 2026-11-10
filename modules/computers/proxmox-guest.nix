{ config, inputs, ... }:
{
  flake.nixosConfigurations.proxmox-guest = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).proxmox-guest.system; }

      config.nixos.modules.thorn-interactive

      config.nixos.modules.desktop-xfce-i3

      config.nixos.modules.services-audio
      config.nixos.modules.services-clamav
      # config.nixos.modules.services-ssh

      config.nixos.modules.thorn-glance

      ../../hosts/proxmox-guest/networking.nix
      config.nixos.modules.hardware-proxmox-guest

      { home-manager.users.thorn = import ../../hosts/proxmox-guest/home.nix; }

      (
        { ... }:
        {
          security.pki.certificates = [
            (builtins.readFile "${inputs.self}/certs/proxmox.guildedthorn.arpa.crt")
          ];

          boot.loader.grub.devices = [ "nodev" ];
          services.qemuGuest.enable = true;

          boot.growPartition = true;
        }
      )
    ];
  };
}
