{ config, inputs, ... }:
{
  flake.nixosConfigurations.proxmox-guest = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.desktop-xfce-i3

      config.nixos.modules.services-audio
      config.nixos.modules.services-clamav
      # config.nixos.modules.services-ssh

      config.nixos.modules.thorn-glance

      "${inputs.self}/hosts/proxmox-guest/networking.nix"
      config.nixos.modules.hardware-proxmox-guest

      { home-manager.users.thorn = import "${inputs.self}/hosts/proxmox-guest/home.nix"; }

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
