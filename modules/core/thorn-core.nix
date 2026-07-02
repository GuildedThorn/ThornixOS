{ config, ... }:
{
  nixos.modules.thorn-core.imports = [
    config.nixos.modules.base
    config.nixos.modules.home-manager-base
    config.nixos.modules.thorn-user
  ];
}
