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
and `zpool status` must report the existing vdevs healthy. This scaffold does
not yet recreate SMB, NFS, Incus, or Docker workloads; those must be restored
in later reviewed configuration changes.
