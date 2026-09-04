{ config, ... }:
{
  nixos.modules.thorn-system-core.imports = [
    config.nixos.modules.base
    config.nixos.modules.thorn-system
    config.nixos.modules.lan-hosts
    config.nixos.modules.services-geoip
    config.nixos.modules.services-backup
  ];

  nixos.modules.thorn-headless.imports = [
    config.nixos.modules.thorn-system-core
    config.nixos.modules.thorn-admin
    config.nixos.modules.services-observability
    config.nixos.modules.services-audit
    config.nixos.modules.services-audit-stack
  ];

  nixos.modules.thorn-interactive.imports = [
    config.nixos.modules.thorn-headless
    config.nixos.modules.home-manager-base
    config.nixos.modules.thorn-user
  ];

  # Compatibility composition for hosts not yet assigned an explicit profile.
  nixos.modules.thorn-core.imports = [ config.nixos.modules.thorn-interactive ];
}
