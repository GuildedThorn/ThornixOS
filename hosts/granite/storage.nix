{ lib, ... }:
{
  # SSH is the recovery path during and immediately after cutover. The shared
  # headless profile keeps SSH closed by default, so explicitly admit it here.
  services.openssh.openFirewall = lib.mkForce true;

  # `platter` is the existing eight-disk, four-mirror data pool. Import it by
  # name at boot, but never let boot-time recovery force an import.
  boot.supportedFilesystems = [ "zfs" ];
  boot.zfs.extraPools = [ "platter" ];
  boot.zfs.forceImportRoot = false;

  # Only the boot-pool is recreated by disko. These explicit boot settings
  # make the storage boundary visible during review.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    device = "nodev";
    efiInstallAsRemovable = true;
  };

  services.zfs.autoScrub = {
    enable = true;
    pools = [ "platter" ];
  };
}
