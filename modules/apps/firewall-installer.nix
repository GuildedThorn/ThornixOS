{ inputs, ... }:
let
  upstreamIsoModule = builtins.readFile "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/iso-image.nix";

  # Upstream's BIOS ISO and serial menu entry are fixed to COM1. This
  # appliance routes its physical USB serial console through COM2/ttyS1.
  serialIsoModule = builtins.toFile "firewall-iso-image.nix" (
    builtins.replaceStrings
      [
        "SERIAL 0 115200"
        "ttyS0"
        "  grubMenuCfg = ''\n    set textmode="
        "terminal_output console"
        "terminal_input  console"
        "../../image/file-options.nix"
        "../../../lib/make-iso9660-image.nix"
      ]
      [
        "SERIAL 1 115200"
        "ttyS1"
        "  grubMenuCfg = ''\n    serial --unit=1 --speed=115200 --word=8 --parity=no --stop=1\n    terminal_input serial console\n    terminal_output serial console\n    set textmode="
        "terminal_output serial console"
        "terminal_input serial console"
        "${inputs.nixpkgs}/nixos/modules/image/file-options.nix"
        "${inputs.nixpkgs}/nixos/lib/make-iso9660-image.nix"
      ]
      upstreamIsoModule
  );

  adminSshKeys = import ../../hosts/firewall/admin-ssh-keys.nix;
in
{
  perSystem =
    { pkgs, system, ... }:
    let
      installer = inputs.nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          "${inputs.nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
          (
            {
              lib,
              modulesPath,
              ...
            }:
            {
              disabledModules = [ "${modulesPath}/installer/cd-dvd/iso-image.nix" ];
              imports = [ serialIsoModule ];

              image.baseName = lib.mkForce "thornix-firewall-installer";
              isoImage = {
                configurationName = "Serial ttyS1";
                forceTextMode = true;
                volumeID = "THORNIX_FIREWALL";
              };

              boot = {
                initrd.availableKernelModules = [
                  "ahci"
                  "ehci_pci"
                  "igb"
                  "ixgbe"
                  "sd_mod"
                  "usb_storage"
                ];
                kernelParams = [
                  "console=tty0"
                  "console=ttyS1,115200n8"
                ];
                loader.timeout = lib.mkForce 5;
              };

              networking = {
                hostName = "firewall-installer";
                enableIPv6 = false;
                useDHCP = false;
                useNetworkd = true;
                networkmanager.enable = lib.mkForce false;
                firewall = {
                  allowedTCPPorts = lib.mkForce [ ];
                  interfaces = {
                    lan.allowedTCPPorts = [ 22 ];
                    opt1.allowedTCPPorts = [ 22 ];
                  };
                };
              };

              systemd.network = {
                enable = true;
                links = {
                  "10-wan" = {
                    matchConfig.PermanentMACAddress = "00:08:a2:0b:12:73";
                    linkConfig = {
                      NamePolicy = "";
                      Name = "wan";
                    };
                  };
                  "10-lan" = {
                    matchConfig.PermanentMACAddress = "00:08:a2:0b:12:75";
                    linkConfig = {
                      NamePolicy = "";
                      Name = "lan";
                    };
                  };
                  "10-opt1" = {
                    matchConfig.PermanentMACAddress = "00:08:a2:0b:12:76";
                    linkConfig = {
                      NamePolicy = "";
                      Name = "opt1";
                    };
                  };
                };
                networks = {
                  "20-wan" = {
                    matchConfig.Name = "wan";
                    networkConfig = {
                      DHCP = "ipv4";
                      IPv6AcceptRA = false;
                      LinkLocalAddressing = "no";
                    };
                  };
                  "30-lan" = {
                    matchConfig.Name = "lan";
                    address = [ "192.168.1.1/24" ];
                    networkConfig = {
                      ConfigureWithoutCarrier = true;
                      IPv6AcceptRA = false;
                      LinkLocalAddressing = "no";
                    };
                  };
                  "30-opt1" = {
                    matchConfig.Name = "opt1";
                    address = [ "172.16.25.1/24" ];
                    networkConfig = {
                      ConfigureWithoutCarrier = true;
                      IPv6AcceptRA = false;
                      LinkLocalAddressing = "no";
                    };
                  };
                };
              };

              # Physical serial console is trusted for this temporary image.
              # Network login remains root/key-only on internal interfaces.
              services.getty.autologinUser = lib.mkForce "root";
              users.users = {
                nixos.initialHashedPassword = lib.mkForce "!";
                root = {
                  initialHashedPassword = lib.mkForce "!";
                  openssh.authorizedKeys.keys = adminSshKeys;
                };
              };
              services.openssh = {
                enable = true;
                openFirewall = false;
                settings = {
                  AllowUsers = [ "root" ];
                  KbdInteractiveAuthentication = false;
                  PasswordAuthentication = false;
                  PermitRootLogin = lib.mkForce "prohibit-password";
                  X11Forwarding = false;
                };
              };

              environment = {
                etc = {
                  "thornixos".source = inputs.self;
                  "thornix-installer-profile".text = "firewall/serial-ttyS1/v1\n";
                };
                systemPackages = with pkgs; [
                  age
                  git
                  sops
                ];
              };
            }
          )
        ];
      };
    in
    {
      packages = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
        firewall-installer-iso = installer.config.system.build.isoImage;
      };
    };
}
