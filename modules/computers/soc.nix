{ config, inputs, ... }:
let
  securityWorkflowReady = builtins.pathExists ../../hosts/soc/security-workflow.nix;
in
{
  flake.nixosConfigurations.soc = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      { nixpkgs.hostPlatform = (import ../../hosts/inventory.nix).soc.system; }

      config.nixos.modules.thorn-headless
      # The VM boots from virtio-scsi. Without the qemu-guest initrd modules
      # soc drops into an emergency shell waiting for
      # /dev/disk/by-partlabel/disk-main-root after a kernel/initrd update.
      config.nixos.modules.hardware-qemu-guest

      # The SIEM host is worth defending too — an attacker who reaches soc
      # can rewrite the record of how they got in.
      config.nixos.modules.services-crowdsec
      config.nixos.modules.services-canary
      config.nixos.modules.services-security-workflow
      config.nixos.modules.services-ssh

      { _module.args.inputs = inputs; }
      { services.qemuGuest.enable = true; }

      ../../hosts/soc/disko.nix
      ../../hosts/soc/networking.nix
      ../../hosts/soc/secrets.nix
      ../../hosts/soc/base.nix
      ../../hosts/soc/monitoring.nix
    ]
    ++ inputs.nixpkgs.lib.optionals securityWorkflowReady [
      ../../hosts/soc/security-workflow.nix
    ];
  };
}
