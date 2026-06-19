{
  inputs,
  config,
  modulesPath,
  lib,
  ...
}:
{

  imports = [
    ./hardware-configuration.nix
    ./disko.nix
    ./networking.nix
    (modulesPath + "/profiles/qemu-guest.nix")

    "${inputs.self}/services/clamav.nix"
    "${inputs.self}/services/ssh.nix"
  ];

  boot.loader.grub.devices = [ "nodev" ];
  services.qemuGuest.enable = true;

  boot.growPartition = true;

}
