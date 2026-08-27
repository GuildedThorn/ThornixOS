{
  lib,
  ...
}:
let
  fleet = import ../inventory.nix;
  fleetDnsRecords = lib.concatMap (
    name:
    let
      host = fleet.${name};
    in
    lib.optional (host.address != null && host.fqdn != null) ''"${host.fqdn}. A ${host.address}"''
  ) (builtins.attrNames fleet);
in
{
  networking = {
    hostName = "firewall";
    enableIPv6 = false;
    nameservers = [ "1.1.1.1" ];
    networkmanager.enable = false;
    useDHCP = false;
    useNetworkd = true;

    nftables.enable = true;
    firewall = {
      enable = true;
      backend = "nftables";
      allowPing = true;
      checkReversePath = "loose";
      filterForward = true;
      trustedInterfaces = [ "wg0" ];

      # thorn-core's observability default targets the fleet's iptables
      # backend. This host repeats that ACL below in native nftables syntax.
      extraCommands = lib.mkForce "";

      interfaces = {
        wan.allowedUDPPorts = [ 4501 ];
        lan = {
          allowedTCPPorts = [
            22
            53
          ];
          allowedUDPPorts = [
            53
            67
          ];
        };
        opt1 = {
          allowedTCPPorts = [
            22
            53
          ];
          allowedUDPPorts = [
            53
            67
          ];
        };
      };

      # pfSense allowed unrestricted routed traffic from all three trusted
      # networks. Public DNAT is intentionally absent until each stale target
      # and protocol is validated during cutover. Retired declarations were
      # TCP/UDP 28000 -> 172.16.25.34, TCP/UDP 15101 -> 172.16.25.33, and
      # TCP/UDP 19132 -> unroutable 172.16.100.20.
      extraForwardRules = ''
        iifname { "lan", "opt1", "wg0" } accept
      '';

      # Baseline observability opens these through iptables. Repeat the narrow
      # source rule in the active nftables firewall backend.
      extraInputRules = ''
        ip saddr 172.16.25.51 tcp dport { 9100, 4243 } accept
      '';
    };

    nat = {
      enable = true;
      externalInterface = "wan";
      internalInterfaces = [
        "lan"
        "opt1"
        "wg0"
      ];
    };
  };

  boot.kernel.sysctl = {
    "net.ipv4.conf.all.forwarding" = true;
    "net.ipv4.conf.default.rp_filter" = 1;
    "net.ipv4.conf.wan.rp_filter" = 1;
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
      "10-unused-sfp" = {
        matchConfig.PermanentMACAddress = "00:08:a2:0b:12:74";
        linkConfig = {
          NamePolicy = "";
          Name = "unused-sfp";
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
      "10-unused-copper-1" = {
        matchConfig.PermanentMACAddress = "00:08:a2:0b:12:77";
        linkConfig = {
          NamePolicy = "";
          Name = "unused-copper-1";
        };
      };
      "10-unused-copper-2" = {
        matchConfig.PermanentMACAddress = "00:08:a2:0b:12:78";
        linkConfig = {
          NamePolicy = "";
          Name = "unused-copper-2";
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
        dhcpV4Config = {
          RouteMetric = 10;
          UseDNS = false;
          UseNTP = false;
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

  services.kea.dhcp4 = {
    enable = true;
    settings = {
      interfaces-config.interfaces = [
        "lan"
        "opt1"
      ];
      lease-database = {
        type = "memfile";
        persist = true;
        name = "/var/lib/kea/dhcp4.leases";
      };
      valid-lifetime = 7200;
      max-valid-lifetime = 86400;
      authoritative = true;
      option-data = [
        {
          name = "domain-name";
          data = "guildedthorn.arpa";
        }
      ];
      client-classes = [
        {
          name = "uefi-x86_64";
          test = "option[93].hex == 0x0007 or option[93].hex == 0x0009";
          option-data = [
            {
              name = "boot-file-name";
              data = "ipxe.efi";
            }
          ];
        }
        {
          name = "legacy-bios";
          test = "not member('uefi-x86_64')";
          option-data = [
            {
              name = "boot-file-name";
              data = "undionly.kpxe";
            }
          ];
        }
      ];
      subnet4 = [
        {
          id = 1;
          subnet = "192.168.1.0/24";
          interface = "lan";
          # Keep the Pineapple's static .31 address outside dynamic leases.
          pools = [
            { pool = "192.168.1.20 - 192.168.1.30"; }
            { pool = "192.168.1.32 - 192.168.1.245"; }
          ];
          next-server = "172.16.25.53";
          option-data = [
            {
              name = "domain-name-servers";
              data = "192.168.1.1";
            }
            {
              name = "routers";
              data = "192.168.1.1";
            }
          ];
          reservations = [
            {
              hw-address = "d8:bb:c1:13:9e:4a";
              ip-address = "192.168.1.6";
              hostname = "nixos";
            }
          ];
        }
        {
          id = 2;
          subnet = "172.16.25.0/24";
          interface = "opt1";
          # Fleet services occupy .25-.64. Keep dynamic clients in a bounded,
          # currently unassigned range and import pfSense's leases at cutover.
          pools = [ { pool = "172.16.25.100 - 172.16.25.199"; } ];
          next-server = "172.16.25.53";
          option-data = [
            {
              name = "domain-name-servers";
              data = "172.16.25.1";
            }
            {
              name = "routers";
              data = "172.16.25.1";
            }
          ];
          reservations = [
            {
              hw-address = "b0:0c:d1:5c:f0:44";
              ip-address = "172.16.25.2";
              hostname = "mitm";
            }
            {
              hw-address = "00:25:00:f4:7e:8c";
              ip-address = "172.16.25.3";
              hostname = "proxmox";
            }
            {
              hw-address = "70:85:c2:55:65:23";
              ip-address = "172.16.25.4";
              hostname = "truenas";
            }
          ];
        }
      ];
    };
  };

  services.unbound = {
    enable = true;
    enableRootTrustAnchor = true;
    resolveLocalQueries = true;
    settings.server = {
      interface = [ "0.0.0.0" ];
      access-control = [
        "127.0.0.0/8 allow"
        "10.10.10.0/24 allow"
        "172.16.25.0/24 allow"
        "192.168.1.0/24 allow"
      ];
      hide-identity = true;
      hide-version = true;
      log-queries = true;
      log-replies = true;
      log-tag-queryreply = true;
      local-zone = [ ''"guildedthorn.arpa." transparent'' ];
      local-data = fleetDnsRecords ++ [
        ''"firewall.guildedthorn.arpa. A 172.16.25.1"''
        ''"pfsense.guildedthorn.arpa. A 172.16.25.1"''
        ''"firewall.guildedthorn.arpa. A 192.168.1.1"''
        ''"pfsense.guildedthorn.arpa. A 192.168.1.1"''
        ''"truenas.guildedthorn.arpa. A 172.16.25.4"''
      ];
    };
  };
}
