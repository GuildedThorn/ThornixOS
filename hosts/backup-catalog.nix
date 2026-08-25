# Canonical recovery contract for stateful ThornixOS services. The SOC joins
# these declarations to success metrics emitted only after the matching
# backup and application-aware restore complete.
let
  managed =
    {
      id,
      host ? id,
      metricHost ? host,
      metricDataset ? host,
      services,
      backupTimer ? "restic-backups-${host}.timer",
    }:
    {
      inherit
        id
        host
        metricHost
        metricDataset
        services
        backupTimer
        ;
      protection = "off-host-restic";
      restoreTimer = "thorn-backup-restore-test.timer";
      maxAgeHours = 36;
      restoreMaxAgeHours = 192;
    };
in
[
  (managed {
    id = "anvil-state";
    host = "anvil";
    services = [ "step-ca" ];
  })
  (managed {
    id = "atlas-state";
    host = "atlas";
    services = [ "netbox" ];
  })
  (managed {
    id = "casebook-state";
    host = "casebook";
    services = [ "thehive" ];
  })
  (managed {
    id = "courier-state";
    host = "courier";
    services = [ "stalwart" ];
  })
  (managed {
    id = "forge-state";
    host = "forge";
    services = [
      "hydra"
      "thornix-promotion"
    ];
  })
  (managed {
    id = "herald-state";
    host = "herald";
    services = [ "ntfy" ];
  })
  (managed {
    id = "hound-state";
    host = "hound";
    services = [ "velociraptor" ];
  })
  (managed {
    id = "identity-state";
    host = "identity";
    services = [ "authentik" ];
  })
  (managed {
    id = "loom-state";
    host = "loom";
    services = [ "n8n" ];
  })
  (managed {
    id = "proxmox-state";
    host = "mac";
    metricHost = "proxmox";
    services = [ "proxmox" ];
  })
  (managed {
    id = "home-assistant-state";
    host = "mitm";
    services = [
      "casita"
      "home-assistant"
      "nabu-casa"
    ];
  })
  (managed {
    id = "oracle-state";
    host = "oracle";
    services = [ "opencti" ];
  })
  (managed {
    id = "sieve-state";
    host = "sieve";
    services = [ "greenbone" ];
  })
  (managed {
    id = "websites-state";
    host = "websites";
    services = [ "owncast" ];
  })
  (managed {
    id = "soc-state";
    host = "soc";
    metricDataset = "soc";
    backupTimer = "restic-backups-prometheus.timer";
    services = [
      "grafana"
      "prometheus"
    ];
  })
  {
    id = "truenas-app-state";
    host = "truenas";
    metricHost = "truenas";
    metricDataset = "truenas";
    services = [
      "jellyfin"
      "seaweedfs"
    ];
    protection = "external-unverified";
    backupTimer = null;
    restoreTimer = null;
    maxAgeHours = 36;
    restoreMaxAgeHours = 192;
  }
]
