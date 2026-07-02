{ config, inputs, ... }:
{
  flake.nixosConfigurations.mac = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.desktop-hyprland
      config.nixos.modules.processor-intel
      config.nixos.modules.graphics-amd

      config.nixos.modules.services-clamav
      config.nixos.modules.services-proxmox
      config.nixos.modules.services-ssh

      "${inputs.self}/hosts/mac/disko.nix"
      "${inputs.self}/hosts/mac/networking.nix"

      (
        { ... }:
        {
          boot.loader.systemd-boot.enable = true;
          boot.loader.efi.canTouchEfiVariables = true;

          # TODO: set this to mac's real LAN IP before deploying.
          services.proxmox-ve.ipAddress = "192.168.1.2";
        }
      )
    ];
  };
}
