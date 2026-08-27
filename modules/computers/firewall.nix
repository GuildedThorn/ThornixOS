{
  config,
  inputs,
  ...
}:
let
  adminSshKeys = import ../../hosts/firewall/admin-ssh-keys.nix;
  systemDisk = "/dev/disk/by-id/wwn-0x500a075112236e91";
in
{
  flake.nixosConfigurations.firewall = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-ssh
      config.nixos.modules.services-suricata

      "${inputs.self}/hosts/firewall/disko.nix"
      "${inputs.self}/hosts/firewall/networking.nix"
      "${inputs.self}/hosts/firewall/secrets.nix"
      "${inputs.self}/hosts/firewall/telemetry.nix"

      (
        {
          config,
          lib,
          pkgs,
          ...
        }:
        {
          boot = {
            initrd.availableKernelModules = [
              "ahci"
              "ehci_pci"
              "igb"
              "ixgbe"
              "sd_mod"
              "usb_storage"
            ];
            kernelModules = [ "kvm-intel" ];
            kernelParams = [
              "console=tty0"
              "console=ttyS1,115200n8"
            ];
            loader.grub = {
              enable = true;
              devices = lib.mkForce [ systemDisk ];
              efiSupport = false;
              extraConfig = ''
                serial --unit=1 --speed=115200 --word=8 --parity=no --stop=1
                terminal_input serial console
                terminal_output serial console
              '';
            };
          };

          hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
          services.getty.autologinUser = null;

          services.openssh = {
            openFirewall = false;
            settings = {
              AllowUsers = [ "root" ];
              KbdInteractiveAuthentication = false;
              PasswordAuthentication = false;
              PermitRootLogin = "prohibit-password";
              X11Forwarding = false;
            };
          };
          users.users.root = {
            initialHashedPassword = "!";
            openssh.authorizedKeys.keys = adminSshKeys;
          };
          services.sshguard.enable = true;

          services.lldpd = {
            enable = true;
            extraArgs = [
              "-I"
              "lan,opt1"
            ];
          };
          services.smartd = {
            enable = true;
            autodetect = true;
          };
          services.vnstat.enable = true;
          thorn.audit.execScope = "all";

          # Match pfSense's WAN IDS placement while adding both routed LANs to
          # HOME_NET. The shared module keeps this alert-only, not inline IPS.
          thorn.suricata.interfaces = [ "wan" ];
          thorn.suricata.bpfFilter = "ip or ip6 or arp";
          services.suricata.settings.vars.address-groups.HOME_NET = lib.mkForce (
            "[192.168.1.0/24,172.16.25.0/24,10.10.10.0/24,127.0.0.0/8]"
          );

          environment.systemPackages = with pkgs; [
            ethtool
            wireguard-tools
          ];
        }
      )
    ];
  };
}
