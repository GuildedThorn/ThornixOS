{ config, ... }:
{
  nixos.modules.profile-qemu-server =
    { lib, ... }:
    {
      imports = [
        config.nixos.modules.thorn-headless
        config.nixos.modules.services-ssh
        config.nixos.modules.hardware-qemu-guest
      ];

      # Headless services are the primary attack surface on these VMs.
      thorn.audit.execScope = "all";

      boot = {
        growPartition = true;
        loader.grub = {
          enable = true;
          devices = lib.mkForce [ "/dev/sda" ];
          efiSupport = false;
        };
        kernelParams = [ "net.ifnames=0" ];
      };

      fileSystems."/".autoResize = true;
      services.qemuGuest.enable = true;

      services.openssh = {
        enable = true;
        openFirewall = false;
        settings = {
          AllowUsers = [ "root" ];
          KbdInteractiveAuthentication = false;
          PasswordAuthentication = false;
          PermitRootLogin = "prohibit-password";
          X11Forwarding = false;
        };
      };

      users.users.root.initialHashedPassword = "!";
    };
}
