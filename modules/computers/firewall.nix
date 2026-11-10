{
  config,
  inputs,
  ...
}:
{
  flake.nixosConfigurations.firewall = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).firewall.system; }

      config.nixos.modules.thorn-headless

      config.nixos.modules.services-ssh
      config.nixos.modules.services-suricata

      ../../hosts/firewall/disko.nix
      ../../hosts/firewall/networking.nix
      ../../hosts/firewall/secrets.nix
      ../../hosts/firewall/telemetry.nix
      ../../hosts/firewall/health.nix

      ../../hosts/firewall/system.nix
    ];
  };
}
