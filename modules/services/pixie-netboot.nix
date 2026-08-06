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
      brandImage = "${inputs.self}/pictures/FullLogo.png";

      bootMenu = pkgs.writeText "pixie-boot.ipxe" ''
        #!ipxe

        # Graphical console support is intentionally limited to UEFI by the
        # upstream iPXE build. Legacy BIOS clients fall through to the same
        # menu using their native text console.
        :start
        iseq ''${platform} efi && goto branded || goto menu

        :branded
        console --picture http://${address}/brand.png --left 128 --right 128 --top 640 --bottom 64 --keep || goto menu
        colour --basic 0 --rgb 0x000010 0
        colour --basic 1 --rgb 0xff5a1f 1
        colour --basic 3 --rgb 0xffc857 3
        colour --basic 7 --rgb 0xf7f3e8 7
        cpair --foreground 7 --background 4 0
        cpair --foreground 7 --background 4 1
        cpair --foreground 0 --background 3 2
        cpair --foreground 3 --background 4 3
        cpair --foreground 0 --background 3 4
        cpair --foreground 7 --background 1 5
        cpair --foreground 3 --background 4 6
        cpair --foreground 0 --background 3 7

        :menu
        menu GuildedThorn  //  PIXIE
        item --gap --             STARTUP
        item --key l local        [L] Continue to local disk (default)
        item --gap --             RECOVERY & INSTALLATION
        item --key r thornix      [R] ThornixOS rescue / NixOS installer - locked flake
        item --key n netbootxyz   [N] netboot.xyz - upstream installers and diagnostics
        item --gap --             FIRMWARE TOOLS
        item --key s shell        [S] Open the iPXE command shell
        item --key b reboot       [B] Reboot this machine
        choose --default local --timeout 10000 target || goto local
        goto ''${target}

        :thornix
        echo
        echo Loading the ThornixOS rescue environment...
        kernel http://${address}/thornix/bzImage init=${rescueSystem.config.system.build.toplevel}/init initrd=initrd ${rescueKernelParams} || goto failed
        initrd http://${address}/thornix/initrd || goto failed
        boot || goto failed

        :netbootxyz
        echo
        echo Loading netboot.xyz from the Internet...
        chain --autofree https://boot.netboot.xyz || chain --autofree http://boot.netboot.xyz || goto failed
        goto start

        :shell
        shell
        goto start

        :reboot
        reboot

        :local
        exit

        :failed
        echo
        echo Pixie could not start the selected target.
        echo Check the network connection or choose another option.
        echo Returning to the menu in three seconds...
        sleep 3
        goto start
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
          name = "brand.png";
          path = brandImage;
        }
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
