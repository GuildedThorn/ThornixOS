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

    nftables = {
      enable = true;
      tables.thorn-egress = {
        family = "inet";
        content = ''
          chain forward {
            type filter hook forward priority -10; policy accept;

            # A compromised honeypot may fetch updates over HTTPS and sync
            # time, but must not initiate arbitrary Internet connections.
            ip saddr 172.16.25.58 oifname "wan" ct state established,related accept
            ip saddr 172.16.25.58 oifname "wan" tcp dport 443 accept
            ip saddr 172.16.25.58 oifname "wan" udp dport 123 accept
            ip saddr 172.16.25.58 oifname "wan" limit rate 5/second burst 20 packets log prefix "lure-egress-denied: " level warn counter drop
          }
        '';
      };
    };
    firewall = {
      enable = true;
      backend = "nftables";
      allowPing = true;
      checkReversePath = true;
      filterForward = true;
      logRefusedConnections = true;
      logRefusedPackets = true;
      logReversePathDrops = true;

      # thorn-core's observability default targets the fleet's iptables
      # backend. This host repeats that ACL below in native nftables syntax.
      extraCommands = lib.mkForce "";

      interfaces = {
        wan.allowedUDPPorts = [ 4501 ];
        lan = {
          allowedTCPPorts = [ 53 ];
          allowedUDPPorts = [
            53
            67
            123
            4501
          ];
        };
        opt1 = {
          allowedTCPPorts = [ 53 ];
          allowedUDPPorts = [
            53
            67
            123
          ];
        };
        wg0 = {
          allowedTCPPorts = [ 53 ];
          allowedUDPPorts = [
            53
            123
          ];
        };
      };

      # Keep each routed network as a separate trust zone. NixOS supplies the
      # established/related return rule and NAT's internal-to-WAN rule; only
      # these documented new cross-zone connections are admitted.
      extraForwardRules = ''
        # Ordinary clients: Home Assistant, Authentik, ntfy, Vaultwarden, Jellyfin, and mail.
        iifname "lan" ip daddr { 172.16.25.2, 172.16.25.52, 172.16.25.63, 172.16.25.65 } tcp dport 443 accept
        iifname "lan" ip daddr 172.16.25.4 tcp dport 8920 accept
        iifname "lan" ip daddr 172.16.25.64 tcp dport { 465, 587, 993 } accept
        iifname "wg0" ip daddr { 172.16.25.2, 172.16.25.52, 172.16.25.63, 172.16.25.65 } tcp dport 443 accept
        iifname "wg0" ip daddr 172.16.25.4 tcp dport 8920 accept
        iifname "wg0" ip daddr 172.16.25.64 tcp dport { 465, 587, 993 } accept

        # Lure intentionally exposes only its declared decoy protocol set.
        iifname { "lan", "wg0" } ip daddr 172.16.25.58 tcp dport { 21, 23, 80, 443, 1433, 2222, 3306, 3389, 5900, 6379, 8080, 9418, 27017 } accept
        iifname { "lan", "wg0" } ip daddr 172.16.25.58 udp dport { 69, 123, 5060 } accept

        # The fixed workstation and Scout's home Wi-Fi are LAN admin endpoints.
        iifname "lan" ether saddr d8:bb:c1:13:9e:4a ip saddr 192.168.1.6 ip daddr 172.16.25.0/24 tcp dport { 22, 443 } accept
        iifname "lan" ether saddr d8:bb:c1:13:9e:4a ip saddr 192.168.1.6 ip daddr 172.16.25.3 tcp dport 8006 accept
        iifname "lan" ether saddr d8:bb:c1:13:9e:4a ip saddr 192.168.1.6 ip daddr 172.16.25.4 tcp dport { 8920, 30008, 30304 } accept
        iifname "lan" ether saddr d8:bb:c1:13:9e:4a ip saddr 192.168.1.6 ip daddr 172.16.25.50 tcp dport 8090 accept
        iifname "lan" ether saddr d8:bb:c1:13:9e:4a ip saddr 192.168.1.6 ip daddr 172.16.25.51 tcp dport { 3000, 3100, 9090 } accept
        iifname "lan" ether saddr d8:bb:c1:13:9e:4a ip saddr 192.168.1.6 ip daddr 172.16.25.53 tcp dport 80 accept
        iifname "lan" ether saddr d8:bb:c1:13:9e:4a ip saddr 192.168.1.6 ip daddr 172.16.25.57 tcp dport 8000 accept
        iifname "lan" ether saddr 64:bc:58:4f:db:9d ip saddr 192.168.1.74 ip daddr 172.16.25.0/24 tcp dport { 22, 443 } accept
        iifname "lan" ether saddr 64:bc:58:4f:db:9d ip saddr 192.168.1.74 ip daddr 172.16.25.3 tcp dport 8006 accept
        iifname "lan" ether saddr 64:bc:58:4f:db:9d ip saddr 192.168.1.74 ip daddr 172.16.25.4 tcp dport { 30304, 8920 } accept
        iifname "lan" ether saddr 64:bc:58:4f:db:9d ip saddr 192.168.1.74 ip daddr 172.16.25.50 tcp dport 8090 accept
        iifname "lan" ether saddr 64:bc:58:4f:db:9d ip saddr 192.168.1.74 ip daddr 172.16.25.51 tcp dport { 3000, 3100, 9090 } accept
        iifname "lan" ether saddr 64:bc:58:4f:db:9d ip saddr 192.168.1.74 ip daddr 172.16.25.53 tcp dport 80 accept
        iifname "lan" ether saddr 64:bc:58:4f:db:9d ip saddr 192.168.1.74 ip daddr 172.16.25.57 tcp dport 8000 accept

        # Clustered Technitium resolvers. Administration uses each node's
        # ACME-backed nginx endpoint on the already restricted port 443.
        iifname "lan" ip daddr { 172.16.25.2, 172.16.25.66 } meta l4proto { tcp, udp } th dport 53 accept
        iifname "wg0" ip daddr { 172.16.25.2, 172.16.25.66 } meta l4proto { tcp, udp } th dport 53 accept
        iifname "lan" ip daddr { 172.16.25.2, 172.16.25.66 } tcp dport 443 accept
        # Keep the resolver administration UI unavailable to routed TR1200
        # clients while preserving access for individually addressed peers.
        iifname "wg0" ip saddr 10.10.10.0/24 ip daddr { 172.16.25.2, 172.16.25.66 } tcp dport 443 accept

        # PXE and the Pineapple sensor cross from LAN into OPT1.
        iifname "lan" ip daddr 172.16.25.53 tcp dport 80 accept
        iifname "lan" ip daddr 172.16.25.53 udp dport 69 accept
        iifname "wg0" ip saddr 172.20.120.0/24 ip daddr 172.16.25.53 tcp dport 80 accept
        iifname "lan" ip saddr 192.168.1.31 ip daddr 172.16.25.2 tcp dport 443 accept
        iifname "lan" ip saddr 192.168.1.31 ip daddr 172.16.25.51 tcp dport 5514 accept

        # Explicit OPT1 services that initiate connections into LAN.
        iifname "opt1" ip saddr 172.16.25.2 ip daddr 192.168.1.6 tcp dport 11435 accept
        iifname "opt1" ip saddr 172.16.25.3 ip daddr 192.168.1.6 tcp dport 22 accept
        iifname "opt1" ip saddr 172.16.25.51 ip daddr 192.168.1.6 tcp dport { 4243, 9100 } accept

        # Scout and the TR1200 are the WireGuard administrative peers.
        iifname "wg0" ip saddr 10.10.10.4/31 ip daddr 172.16.25.0/24 tcp dport { 22, 443 } accept
        iifname "wg0" ip saddr 10.10.10.4/31 ip daddr 172.16.25.3 tcp dport 8006 accept
        iifname "wg0" ip saddr 10.10.10.4/31 ip daddr 172.16.25.4 tcp dport { 30304, 8920 } accept
        iifname "wg0" ip saddr 10.10.10.4/31 ip daddr 172.16.25.50 tcp dport 8090 accept
        iifname "wg0" ip saddr 10.10.10.4/31 ip daddr 172.16.25.51 tcp dport { 3000, 3100, 9090 } accept
        iifname "wg0" ip saddr 10.10.10.4/31 ip daddr 172.16.25.53 tcp dport 80 accept
        iifname "wg0" ip saddr 10.10.10.4/31 ip daddr 172.16.25.57 tcp dport 8000 accept
      '';

      # Limit firewall administration to fixed administrator endpoints and pin
      # observability to the SOC's physical ingress interface as well as source.
      extraInputRules = ''
        iifname "lan" ether saddr d8:bb:c1:13:9e:4a ip saddr 192.168.1.6 tcp dport 22 accept
        iifname "lan" ether saddr 64:bc:58:4f:db:9d ip saddr 192.168.1.74 tcp dport 22 accept
        iifname "opt1" ip saddr 172.16.25.3 tcp dport 22 accept
        iifname "wg0" ip saddr 10.10.10.4/31 tcp dport 22 accept
        iifname "opt1" ip saddr 172.16.25.51 tcp dport { 9100, 4243, 9167, 9547 } accept
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
    "net.ipv4.conf.all.rp_filter" = 1;
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
      control-socket = {
        socket-type = "unix";
        socket-name = "/run/kea/kea4-ctrl-socket";
      };
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
              data = "172.16.25.66, 172.16.25.2, 192.168.1.1";
            }
            {
              name = "routers";
              data = "192.168.1.1";
            }
            {
              name = "ntp-servers";
              data = "192.168.1.1";
            }
          ];
          reservations = [
            {
              hw-address = "d8:bb:c1:13:9e:4a";
              ip-address = "192.168.1.6";
              hostname = "nixos";
            }
            {
              hw-address = "64:bc:58:4f:db:9d";
              ip-address = "192.168.1.74";
              hostname = "scout";
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
              data = "172.16.25.66, 172.16.25.2, 172.16.25.1";
            }
            {
              name = "routers";
              data = "172.16.25.1";
            }
            {
              name = "ntp-servers";
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

  services.chrony = {
    enable = true;
    extraConfig = ''
      allow 10.10.10.0/24
      allow 172.16.25.0/24
      allow 192.168.1.0/24
      makestep 1.0 3
    '';
  };

  services.unbound = {
    enable = true;
    enableRootTrustAnchor = true;
    localControlSocketPath = "/run/unbound/unbound.ctl";
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
      extended-statistics = true;
      log-queries = false;
      log-replies = false;
      log-tag-queryreply = false;
      # Static prevents unknown internal names from escaping to a future
      # public forwarder and looping through Technitium's conditional zone.
      local-zone = [ ''"guildedthorn.arpa." static'' ];
      local-data = fleetDnsRecords ++ [
        ''"firewall.guildedthorn.arpa. A 172.16.25.1"''
        ''"mitm.dns-cluster.guildedthorn.arpa. A 172.16.25.2"''
        ''"pfsense.guildedthorn.arpa. A 172.16.25.1"''
        ''"resolver.dns-cluster.guildedthorn.arpa. A 172.16.25.66"''
        ''"resolver2.guildedthorn.arpa. A 172.16.25.2"''
        ''"search.guildedthorn.arpa. A 172.16.25.67"''
        ''"feeds.guildedthorn.arpa. A 172.16.25.67"''
        ''"rss-bridge.guildedthorn.arpa. A 172.16.25.67"''
        ''"_dns.resolver.arpa. 3600 IN SVCB 1 resolver.guildedthorn.arpa. alpn=h2 dohpath=/dns-query{?dns}"''
        ''"_dns.resolver.arpa. 3600 IN SVCB 2 resolver2.guildedthorn.arpa. alpn=h2 dohpath=/dns-query{?dns}"''
        ''"firewall.guildedthorn.arpa. A 192.168.1.1"''
        ''"pfsense.guildedthorn.arpa. A 192.168.1.1"''
        ''"truenas.guildedthorn.arpa. A 172.16.25.4"''
      ];
    };
  };
}
