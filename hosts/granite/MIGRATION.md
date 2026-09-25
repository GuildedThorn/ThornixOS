# TrueNAS → NixOS migration: granite

## Safety boundary

Live inventory on 2026-09-21:

- OS pool: `boot-pool`, on the 112 GB SanDisk boot disk (`/dev/sda`)
- Data pool: `platter`, 7.25 TB, four mirrors across eight WDC disks
- Both pools were `ONLINE`; latest scrubs repaired `0B` with no errors
- Data pool datasets are mounted below `/mnt/platter`

The only device described by `disko.nix` is:

```text
/dev/disk/by-id/ata-SanDisk_SDSSDA120G_172450461108
```

`platter` is intentionally not present in disko. It is only named in
`boot.zfs.extraPools`, and forced root-pool imports are disabled.

Do not run `disko`, `nixos-anywhere`, `zpool import`, `zpool export`, `zfs
load-key`, or any mount command against the live TrueNAS installation during
planning. The destructive action is limited to the boot disk and must be
performed only after a generated-script review and a disposable VM rehearsal.

## Cutover outline

1. Build and inspect `.#nixosConfigurations.granite.config.system.build.diskoScript`.
2. Add a VM check with one disposable boot disk and a separate fake `platter`
   pool. Verify disko changes only the fake boot disk and sentinel data survives.
3. Export any TrueNAS configuration and record SMB, NFS, Incus, app, SMART, and
   UPS details before shutting down the appliance.
4. Boot a NixOS installer in RAM and run a preflight that resolves the SanDisk
   by-id path to the 112 GB boot disk. Abort if any data-pool device resolves to
   the disko target.
5. Run the reviewed install against the boot disk only, reboot, and verify
   `zpool status`, dataset mounts, and ZFS event health before restoring services.
6. Recreate SMB/NFS/Incus and application state declaratively in separate
   reviewed changes. Do not silently invent ACLs, credentials, encrypted
   dataset keys, or application databases.

The new hostname is `granite`; the address remains `172.16.25.4`.

## Immich

Immich is declared in `modules/services/immich.nix` and served at
`https://immich.guildedthorn.arpa`. The migration preserves the existing
TrueNAS datasets instead of creating new storage:

- uploads: `platter/ix-apps/app_mounts/immich/data`
- PostgreSQL 18 cluster: `platter/ix-apps/app_mounts/immich/postgres_data/18/docker`
- database role/database: `immich` / `immich`

Those datasets were created with `canmount=noauto`; `immich-datasets.service`
mounts them explicitly before the four Immich containers start. The service
uses host networking so the containers can reach the preserved PostgreSQL and
Redis services without relying on mutable container-network DNS.

The database password is intentionally not in Git. It is stored mode `0600` in
`/etc/immich.env` on `granite`. If the host is rebuilt, recreate that file
before starting `podman-immich-postgres.service` and
`podman-immich-server.service`.

## Monitoring and alerts

Granite is enrolled in the existing SOC monitoring stack. The host runs:

- Prometheus Node Exporter on TCP `9100`, restricted to the SOC host;
- Alloy, forwarding the systemd journal to the SOC Loki instance;
- `smartd` for drive health and SMART failures; and
- `zfs-zed` for pool, vdev, checksum, and other ZFS events.

The SOC Prometheus and Grafana configuration already applies the fleet-wide
alerts to Granite: host-down and scrape failures, failed systemd services,
disk pressure, SMART failures, and ZFS/journal health events. Granite's
monitoring enrollment is gated by `hosts/granite/telemetry.nix` and the
`readyFiles` entry in `hosts/inventory.nix`, so it will not become a monitored
target accidentally before its telemetry configuration exists.

Verify enrollment from the SOC host:

```sh
curl -sS http://127.0.0.1:9091/api/v1/query \
  --data-urlencode 'query=up{instance="granite.guildedthorn.arpa:9100"}'
```

The result should contain a sample with value `"1"`.

## Deployment commands

The commands below assume the repository is checked out locally and the
workstation key is installed for the TrueNAS root account. They use `path:` so
the working tree's new, possibly-uncommitted granite files are included.

Before the change window, build the system and inspect the generated disko
script:

```sh
cd /home/thorn/Desktop/ThornixOS

nix build path:.#nixosConfigurations.granite.config.system.build.toplevel \
  --no-link

nix build path:.#nixosConfigurations.granite.config.system.build.diskoScript \
  --no-link --print-out-paths
```

Verify the current SSH path:

```sh
ssh -i /home/thorn/.ssh/id_ed25519 root@172.16.25.4 hostname
```

### Phase 1: kexec only

This loads a temporary NixOS installer into memory. It must not format or
repartition disks:

```sh
nix run nixpkgs#nixos-anywhere -- \
  --flake "path:$PWD#granite" \
  --target-host root@172.16.25.4 \
  --phases kexec
```

### Phase 2: installer preflight

Reconnect to the temporary installer and inspect the disks:

```sh
ssh -i /home/thorn/.ssh/id_ed25519 root@172.16.25.4

lsblk -o NAME,SIZE,MODEL,SERIAL,FSTYPE,MOUNTPOINTS
readlink -f /dev/disk/by-id/ata-SanDisk_SDSSDA120G_172450461108
```

The SanDisk device must be the 112 GB boot disk. All eight WDC devices must
remain separate data devices. Abort if the by-id path resolves to any data
disk, or if the hardware inventory is not what was reviewed.

### Phase 3: destructive install

Only after the preflight passes, run the install. This is the point where
disko recreates the boot disk:

```sh
nix run nixpkgs#nixos-anywhere -- \
  --flake "path:$PWD#granite" \
  --target-host root@172.16.25.4 \
  --phases disko,install,reboot
```

Do not add `platter` or any WDC device to `disko.nix`.

### Phase 4: post-reboot verification

After the machine reboots, verify the new identity and data pool before
restoring any services:

```sh
ssh -i /home/thorn/.ssh/id_ed25519 root@172.16.25.4 hostname

ssh -i /home/thorn/.ssh/id_ed25519 root@172.16.25.4 \
  'zpool status && zfs list'
```

The expected hostname is `granite`, the existing pool must be named `platter`,
and `zpool status` must report the existing vdevs healthy. After the service
configuration is applied, verify Immich without touching the pool layout:

```sh
ssh -i /home/thorn/.ssh/id_ed25519 root@172.16.25.4 \
  'systemctl is-active immich-datasets podman-immich-postgres podman-immich-redis podman-immich-server podman-immich-machine-learning'

curl -I https://immich.guildedthorn.arpa/
```

The scaffold recreates the migrated Immich workload, SMB, NFS, Incus, and
other services as separate reviewed configuration changes. It does not
recreate or format the `platter` pool.
