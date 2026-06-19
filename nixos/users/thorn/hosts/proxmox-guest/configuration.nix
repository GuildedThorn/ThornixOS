{
  inputs,
  modulesPath,
  ...
}:
{

  imports = [
    ./networking.nix
    ./hardware-configuration.nix
    (modulesPath + "/profiles/qemu-guest.nix")

    "${inputs.self}/desktop/xfce+i3.nix"

    "${inputs.self}/services/audio.nix"
    "${inputs.self}/services/clamav.nix"
    #"${inputs.self}/services/ssh.nix"

    "${inputs.self}/users/thorn/services/glance.nix"
  ];

  security.pki.certificates = [
    (builtins.readFile "${inputs.self}/users/thorn/certs/proxmox.guildedthorn.arpa.crt")
  ];

  home-manager.users.thorn = import ./home.nix;
  boot.loader.grub.devices = [ "nodev" ];
  services.qemuGuest.enable = true;

  boot.growPartition = true;
}
