{ config, inputs, ... }:
let
  adminSshKeys = import ../../hosts/anvil/admin-ssh-keys.nix;
  caMaterialReady =
    builtins.pathExists "${inputs.self}/certs/anvil-intermediate.crt"
    && builtins.pathExists "${inputs.self}/hosts/anvil/secrets.yaml";
in
{
  flake.nixosConfigurations.anvil = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.profile-qemu-server

      config.nixos.modules.services-anvil-ca
      config.nixos.modules.services-canary
      "${inputs.self}/hosts/anvil/disko.nix"
      "${inputs.self}/hosts/anvil/networking.nix"

      {
        users.users.root.openssh.authorizedKeys.keys = adminSshKeys;
      }
    ]
    ++ inputs.nixpkgs.lib.optional caMaterialReady "${inputs.self}/hosts/anvil/secrets.nix";
  };
}
