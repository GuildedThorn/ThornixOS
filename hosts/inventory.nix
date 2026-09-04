# Authoritative ThornixOS fleet membership. Consumers must derive deployment,
# CI, and monitoring membership from this file instead of maintaining their
# own hostname lists.
let
  mkHost =
    {
      address ? null,
      class ? "server",
      deploy ? production,
      fqdn ? null,
      monitoring ? { },
      production ? true,
      role,
      system ? "x86_64-linux",
    }:
    {
      inherit
        address
        class
        fqdn
        production
        role
        ;
      inherit system;
      deployment = {
        enable = deploy;
        branch = if production then "production" else null;
      };
      monitoring = {
        mode = "disabled";
        journal = false;
        canary = false;
        readyFiles = [ ];
        probes = [ ];
      }
      // monitoring;
    };
in
{
  anvil = mkHost {
    address = "172.16.25.55";
    fqdn = "anvil.guildedthorn.arpa";
    role = "pki";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [
        "certs/anvil-intermediate.crt"
        "hosts/anvil/secrets.yaml"
      ];
      probes = [ "https://anvil.guildedthorn.arpa/health" ];
    };
  };

  atlas = mkHost {
    address = "172.16.25.54";
    fqdn = "atlas.guildedthorn.arpa";
    role = "inventory";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      probes = [ "https://atlas.guildedthorn.arpa/" ];
    };
  };

  casebook = mkHost {
    address = "172.16.25.59";
    fqdn = "casebook.guildedthorn.arpa";
    role = "incident-response";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/casebook/telemetry.nix" ];
      probes = [ "https://casebook.guildedthorn.arpa/" ];
    };
  };

  courier = mkHost {
    address = "172.16.25.64";
    fqdn = "courier.guildedthorn.arpa";
    role = "mail";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/courier/telemetry.nix" ];
      probes = [ "https://courier.guildedthorn.arpa/admin" ];
    };
  };

  codex = mkHost {
    address = "172.16.25.67";
    fqdn = "codex.guildedthorn.arpa";
    role = "personal-information";
    monitoring = {
      mode = "scrape";
      probes = [
        "https://search.guildedthorn.arpa/"
        "https://feeds.guildedthorn.arpa/healthcheck"
        "https://rss-bridge.guildedthorn.arpa/?action=health"
      ];
    };
  };

  deck = mkHost {
    address = "172.16.25.26";
    class = "handheld";
    deploy = false;
    fqdn = "deck.guildedthorn.arpa";
    production = false;
    role = "gaming-voice-satellite";
    monitoring = {
      mode = "scrape";
      probes = [ "http://172.16.25.26:10701/api/health" ];
    };
  };

  firewall = mkHost {
    address = "172.16.25.1";
    fqdn = "firewall.guildedthorn.arpa";
    role = "edge-firewall";
    monitoring = {
      mode = "scrape";
      journal = true;
      readyFiles = [ "hosts/firewall/telemetry.nix" ];
    };
  };

  forge = mkHost {
    address = "172.16.25.61";
    fqdn = "forge.guildedthorn.arpa";
    role = "continuous-integration";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/forge/telemetry.nix" ];
      probes = [ "https://forge.guildedthorn.arpa/" ];
    };
  };

  herald = mkHost {
    address = "172.16.25.63";
    fqdn = "herald.guildedthorn.arpa";
    role = "notifications";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/herald/telemetry.nix" ];
      probes = [ "https://herald.guildedthorn.arpa/v1/health" ];
    };
  };

  hound = mkHost {
    address = "172.16.25.57";
    fqdn = "hound.guildedthorn.arpa";
    role = "endpoint-response";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/hound/telemetry.nix" ];
      probes = [ "https://hound.guildedthorn.arpa/app/index.html" ];
    };
  };

  identity = mkHost {
    address = "172.16.25.52";
    fqdn = "identity.guildedthorn.arpa";
    role = "identity";
    monitoring = {
      mode = "scrape";
      probes = [ "https://identity.guildedthorn.arpa/" ];
    };
  };

  lure = mkHost {
    address = "172.16.25.58";
    fqdn = "lure.guildedthorn.arpa";
    role = "deception";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/lure/telemetry.nix" ];
    };
  };

  loom = mkHost {
    address = "172.16.25.62";
    fqdn = "loom.guildedthorn.arpa";
    role = "automation";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/loom/telemetry.nix" ];
      probes = [ "https://loom.guildedthorn.arpa/healthz" ];
    };
  };

  mac = mkHost {
    address = "172.16.25.3";
    fqdn = "proxmox.guildedthorn.arpa";
    role = "hypervisor";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      probes = [ "https://proxmox.guildedthorn.arpa:8006/" ];
    };
  };

  mitm = mkHost {
    address = "172.16.25.2";
    fqdn = "mitm.guildedthorn.arpa";
    role = "lab";
    monitoring = {
      mode = "scrape";
      probes = [ "https://resolver2.guildedthorn.arpa/" ];
    };
  };

  nixos = mkHost {
    address = "192.168.1.6";
    class = "workstation";
    fqdn = "nixos.guildedthorn.arpa";
    role = "workstation";
    monitoring = {
      mode = "scrape";
      journal = true;
    };
  };

  oracle = mkHost {
    address = "172.16.25.60";
    fqdn = "oracle.guildedthorn.arpa";
    role = "threat-intelligence";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/oracle/telemetry.nix" ];
      probes = [ "https://oracle.guildedthorn.arpa/" ];
    };
  };

  pixie = mkHost {
    address = "172.16.25.53";
    fqdn = "pixie.guildedthorn.arpa";
    role = "provisioning";
    monitoring = {
      mode = "scrape";
      probes = [ "http://172.16.25.53/boot.ipxe" ];
    };
  };

  proxmox-guest = mkHost {
    class = "template";
    deploy = false;
    production = false;
    role = "proxmox-template";
  };

  resolver = mkHost {
    address = "172.16.25.66";
    fqdn = "resolver.guildedthorn.arpa";
    role = "dns";
    monitoring = {
      mode = "scrape";
      probes = [ "https://resolver.guildedthorn.arpa/" ];
    };
  };

  scout = mkHost {
    class = "laptop";
    fqdn = "scout.guildedthorn.arpa";
    role = "roaming-workstation";
    monitoring = {
      mode = "push";
      journal = true;
    };
  };

  sieve = mkHost {
    address = "172.16.25.56";
    fqdn = "sieve.guildedthorn.arpa";
    role = "vulnerability-scanner";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/sieve/telemetry.nix" ];
      probes = [ "https://sieve.guildedthorn.arpa/" ];
    };
  };

  soc = mkHost {
    address = "172.16.25.51";
    fqdn = "soc.guildedthorn.arpa";
    role = "siem";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      probes = [ "https://soc.guildedthorn.arpa:3000/api/health" ];
    };
  };

  vmware-guest = mkHost {
    class = "template";
    deploy = false;
    production = false;
    role = "vmware-template";
  };

  vmware-test = mkHost {
    class = "test";
    deploy = false;
    production = false;
    role = "vmware-test";
  };

  voice-office = mkHost {
    class = "satellite";
    deploy = false;
    fqdn = "voice-office.guildedthorn.arpa";
    production = false;
    role = "voice-satellite";
    system = "aarch64-linux";
  };

  vault = mkHost {
    address = "172.16.25.65";
    fqdn = "vault.guildedthorn.arpa";
    role = "password-manager";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      readyFiles = [ "hosts/vault/telemetry.nix" ];
      probes = [ "https://vault.guildedthorn.arpa/alive" ];
    };
  };

  websites = mkHost {
    address = "172.16.25.50";
    fqdn = "websites.guildedthorn.arpa";
    role = "web";
    monitoring = {
      mode = "scrape";
      journal = true;
      canary = true;
      probes = [ "https://guildedthorn.com/" ];
    };
  };
}
