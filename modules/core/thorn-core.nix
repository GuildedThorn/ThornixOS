{ config, ... }:
{
  nixos.modules.thorn-core.imports = [
    config.nixos.modules.base
    config.nixos.modules.home-manager-base
    config.nixos.modules.thorn-user
    config.nixos.modules.lan-hosts
    config.nixos.modules.services-observability
    config.nixos.modules.services-audit
  ];
}
