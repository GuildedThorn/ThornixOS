{
  # Fixed /etc/hosts entries for the LAN's static addresses. pfSense's
  # Unbound is authoritative for guildedthorn.arpa, but not every host
  # resolves through pfSense yet (roaming laptop, hosts still on stale
  # deploys) — baking the static addresses in keeps fleet-internal names
  # (Loki push, Prometheus scrapes, S3) working no matter which
  # nameserver a host is using.
  nixos.modules.lan-hosts =
    { ... }:
    {
      networking.hosts = {
        "172.16.25.1" = [ "pfsense.guildedthorn.arpa" ];
        "172.16.25.2" = [ "mitm.guildedthorn.arpa" ];
        "172.16.25.3" = [ "proxmox.guildedthorn.arpa" ];
        "172.16.25.4" = [ "truenas.guildedthorn.arpa" ];
        "172.16.25.50" = [ "websites.guildedthorn.arpa" ];
        "172.16.25.51" = [ "soc.guildedthorn.arpa" ];
        "172.16.25.52" = [ "identity.guildedthorn.arpa" ];
        "172.16.25.53" = [ "pixie.guildedthorn.arpa" ];
        "172.16.25.54" = [ "atlas.guildedthorn.arpa" ];
        "172.16.25.55" = [ "anvil.guildedthorn.arpa" ];
      };
    };
}
