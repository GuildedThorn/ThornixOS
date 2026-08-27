{ config, inputs, ... }:
let
  securityWorkflowReady = builtins.pathExists "${inputs.self}/hosts/soc/security-workflow.nix";
in
{
  flake.nixosConfigurations.soc = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      # The SIEM host is worth defending too — an attacker who reaches soc
      # can rewrite the record of how they got in.
      config.nixos.modules.services-crowdsec
      config.nixos.modules.services-canary
      config.nixos.modules.services-security-workflow
      config.nixos.modules.services-ssh

      { _module.args.inputs = inputs; }

      config.nixos.modules.hardware-qemu-guest
      "${inputs.self}/hosts/soc/disko.nix"
      "${inputs.self}/hosts/soc/networking.nix"
      "${inputs.self}/hosts/soc/secrets.nix"
      "${inputs.self}/hosts/soc/base.nix"
      "${inputs.self}/hosts/soc/monitoring.nix"
    ]
    ++ inputs.nixpkgs.lib.optionals securityWorkflowReady [
      "${inputs.self}/hosts/soc/security-workflow.nix"
    ];
  };
}
