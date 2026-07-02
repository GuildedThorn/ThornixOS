# PLACEHOLDER — this host has not been installed yet. Replace with the real
# output of `nixos-generate-config` once you have actual hardware/disk UUIDs.
{ lib, ... }:
{
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos-root";
    fsType = "ext4";
  };

  boot.loader.grub.devices = [ "/dev/sda" ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
}
