let
  fleet = import ../../hosts/inventory.nix;
  managedHosts = builtins.listToAttrs (
    builtins.concatLists (
      builtins.map (
        name:
        let
          host = fleet.${name};
        in
        if host.address != null && host.fqdn != null then
          [
            {
              name = host.address;
              value = [ host.fqdn ];
            }
          ]
        else
          [ ]
      ) (builtins.attrNames fleet)
    )
  );
in
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
        "172.16.25.4" = [ "truenas.guildedthorn.arpa" ];
      }
      // managedHosts;
    };
}
