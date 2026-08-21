{ lib, ... }:
{
  # Headless: nobody logs in interactively, so the default "sessions" exec
  # scope would record nothing. See services-audit for the volume trade-off.
  thorn.audit.execScope = "all";

  boot = {
    growPartition = true;

    # BIOS boot via GRUB on the whole disk. Disko already registers /dev/sda;
    # force one entry so the definitions do not create a mirroredBoots assert.
    loader.grub = {
      enable = true;
      devices = lib.mkForce [ "/dev/sda" ];
      efiSupport = false;
    };

    # Match the static eth0 configuration in networking.nix.
    kernelParams = [ "net.ifnames=0" ];
  };

  services.qemuGuest.enable = true;
  services.openssh.settings = {
    PermitRootLogin = "prohibit-password";
    PasswordAuthentication = false;
  };

  # Workstation keys — this headless host has no other login path.
  users.users.root.openssh.authorizedKeys.keys = import ./admin-ssh-keys.nix;
}
