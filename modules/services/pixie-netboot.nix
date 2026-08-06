{ inputs, ... }:
{
  nixos.modules.services-pixie-netboot =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      address = "172.16.25.53";
      adminSshKeys = import ../../hosts/pixie/admin-ssh-keys.nix;

      # A locked, key-only NixOS rescue environment. nixos-anywhere can use
      # it directly, while a console still has the ordinary installer tools.
      rescueSystem = inputs.nixpkgs.lib.nixosSystem {
        system = pkgs.stdenv.hostPlatform.system;
        modules = [
          "${inputs.nixpkgs}/nixos/modules/installer/netboot/netboot-minimal.nix"
          (
            { lib, ... }:
            {
              boot = {
                kernelParams = [ "net.ifnames=0" ];
                # A rescue image should never force-import an existing ZFS
                # root pool merely because the machine was network-booted.
                zfs.forceImportRoot = false;
              };
              networking = {
                hostName = "thornix-rescue";
                enableIPv6 = false;
                useDHCP = lib.mkForce true;
                firewall.allowedTCPPorts = [ 22 ];
              };

              services.getty.autologinUser = lib.mkForce null;
              users.users = {
                nixos.initialHashedPassword = lib.mkForce "!";
                root = {
                  initialHashedPassword = lib.mkForce "!";
                  openssh.authorizedKeys.keys = adminSshKeys;
                };
              };
              services.openssh = {
                enable = true;
                settings = {
                  AllowUsers = [ "root" ];
                  KbdInteractiveAuthentication = false;
                  PasswordAuthentication = false;
                  PermitRootLogin = lib.mkForce "prohibit-password";
                  X11Forwarding = false;
                };
              };

              environment.etc."thornix-netboot-profile".text = "pixie-rescue/v1\n";
              system.stateVersion = "25.05";
            }
          )
        ];
      };

      rescueKernel = "${rescueSystem.config.system.build.kernel}/${rescueSystem.config.system.boot.loader.kernelFile}";
      rescueInitrd = "${rescueSystem.config.system.build.netbootRamdisk}/initrd";
      rescueKernelParams = lib.concatStringsSep " " rescueSystem.config.boot.kernelParams;

      bootMenu = pkgs.writeText "pixie-boot.ipxe" ''
        #!ipxe

        :menu
        menu ThornixOS network boot
        item --gap --             Local, reproducible boot targets
        item thornix              ThornixOS rescue / NixOS installer (locked flake)
        item --gap --             Upstream tools (requires Internet access)
        item netbootxyz           netboot.xyz installers and diagnostics
        item --gap --             Firmware actions
        item shell                iPXE shell
        item reboot               Reboot
        item local                Continue to local disk
        choose --default local --timeout 10000 target || goto local
        goto ''${target}

        :thornix
        kernel http://${address}/thornix/bzImage init=${rescueSystem.config.system.build.toplevel}/init initrd=initrd ${rescueKernelParams} || goto failed
        initrd http://${address}/thornix/initrd || goto failed
        boot || goto failed

        :netbootxyz
        chain --autofree https://boot.netboot.xyz || chain --autofree http://boot.netboot.xyz || goto failed
        goto menu

        :shell
        shell
        goto menu

        :reboot
        reboot

        :local
        exit

        :failed
        echo
        echo Boot failed. Returning to the Pixie menu in three seconds.
        sleep 3
        goto menu
      '';

      embeddedBootstrap = pkgs.writeText "pixie-bootstrap.ipxe" ''
        #!ipxe
        dhcp || goto shell
        chain --autofree http://${address}/boot.ipxe || goto shell
        exit

        :shell
        echo Unable to load the Pixie menu from http://${address}/boot.ipxe
        shell
      '';

      pixieIpxe = pkgs.ipxe.override {
        embedScript = embeddedBootstrap;
        enableDefaultPlatformTargets = false;
        additionalTargets = {
          "bin/undionly.kpxe" = null;
          "bin-x86_64-efi/ipxe.efi" = null;
          "bin-x86_64-efi/snp.efi" = null;
        };
        firmwareBinary = "ipxe.efi";
      };

      # atftpd may serve from a chroot. Copy the three small firmware files
      # into one immutable store path instead of relying on external symlinks.
      tftpRoot = pkgs.runCommand "pixie-tftp-root" { } ''
        mkdir -p "$out"
        install -m 0444 ${pixieIpxe}/undionly.kpxe "$out/undionly.kpxe"
        install -m 0444 ${pixieIpxe}/ipxe.efi "$out/ipxe.efi"
        install -m 0444 ${pixieIpxe}/snp.efi "$out/snp.efi"
      '';

      rescueTree = pkgs.linkFarm "pixie-rescue-http" [
        {
          name = "bzImage";
          path = rescueKernel;
        }
        {
          name = "initrd";
          path = rescueInitrd;
        }
      ];
      httpRoot = pkgs.linkFarm "pixie-http-root" [
        {
          name = "boot.ipxe";
          path = bootMenu;
        }
        {
          name = "thornix";
          path = rescueTree;
        }
      ];
    in
    {
      services.atftpd = {
        enable = true;
        root = tftpRoot;
        extraOptions = [
          "--bind-address"
          address
        ];
      };

      services.nginx = {
        enable = true;
        recommendedOptimisation = true;
        virtualHosts."pixie.guildedthorn.arpa" = {
          serverName = "pixie.guildedthorn.arpa";
          root = httpRoot;
          listen = [
            {
              addr = address;
              port = 80;
            }
          ];
          locations."/".extraConfig = ''
            limit_except GET HEAD { deny all; }
            add_header Cache-Control "no-store" always;
          '';
        };
      };

      systemd.services.atftpd.serviceConfig = {
        ProtectHome = true;
        ProtectSystem = "strict";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };

      # PXE is intentionally reachable only from LAN and OPT1. pfSense stays
      # the sole DHCP authority; Pixie has no DHCP or DNS listener.
      networking.firewall.extraCommands = ''
        iptables -w -A nixos-fw -p tcp --dport 80 -s 172.16.25.0/24 -j nixos-fw-accept
        iptables -w -A nixos-fw -p tcp --dport 80 -s 192.168.1.0/24 -j nixos-fw-accept
        iptables -w -A nixos-fw -p udp --dport 69 -s 172.16.25.0/24 -j nixos-fw-accept
        iptables -w -A nixos-fw -p udp --dport 69 -s 192.168.1.0/24 -j nixos-fw-accept
      '';

      # Keep both the HTTP tree and TFTP firmware in the system closure, and
      # expose their resolved paths for simple post-deploy verification.
      environment.etc = {
        "pixie/http-root".source = httpRoot;
        "pixie/tftp-root".source = tftpRoot;
      };

      assertions = [
        {
          assertion = config.networking.hostName == "pixie";
          message = "services-pixie-netboot is a fixed service profile for the pixie host";
        }
      ];
    };
}
