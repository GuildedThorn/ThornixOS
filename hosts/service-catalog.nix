# Canonical catalog for the user-facing and operator-facing services Casita
# can report. Probe URLs are consumed by the SOC; launch URLs are safe links
# for Home Assistant and may intentionally differ from health endpoints.
[
  {
    id = "anvil";
    name = "Anvil";
    role = "PKI and ACME";
    host = "anvil";
    inventoryHost = "anvil";
    probeUrl = "https://anvil.guildedthorn.arpa/health";
    launchUrl = "https://anvil.guildedthorn.arpa/health";
    icon = "mdi:certificate-outline";
    aliases = [
      "anvil"
      "certificate authority"
      "pki"
      "acme"
    ];
  }
  {
    id = "atlas";
    name = "Atlas";
    role = "NetBox inventory";
    host = "atlas";
    inventoryHost = "atlas";
    probeUrl = "https://atlas.guildedthorn.arpa/";
    launchUrl = "https://atlas.guildedthorn.arpa/";
    icon = "mdi:server-network";
    aliases = [
      "atlas"
      "netbox"
      "inventory"
    ];
  }
  {
    id = "casebook";
    name = "Casebook";
    role = "TheHive incident response";
    host = "casebook";
    inventoryHost = "casebook";
    probeUrl = "https://casebook.guildedthorn.arpa/";
    launchUrl = "https://casebook.guildedthorn.arpa/";
    icon = "mdi:briefcase-search-outline";
    aliases = [
      "casebook"
      "the hive"
      "thehive"
      "incident response"
    ];
  }
  {
    id = "courier";
    name = "Courier";
    role = "Stalwart mail";
    host = "courier";
    inventoryHost = "courier";
    probeUrl = "https://courier.guildedthorn.arpa/admin";
    launchUrl = "https://courier.guildedthorn.arpa/admin";
    icon = "mdi:email-fast-outline";
    aliases = [
      "courier"
      "mail"
      "email"
      "stalwart"
    ];
  }
  {
    id = "forge";
    name = "Forge";
    role = "Hydra continuous integration";
    host = "forge";
    inventoryHost = "forge";
    probeUrl = "https://forge.guildedthorn.arpa/";
    launchUrl = "https://forge.guildedthorn.arpa/";
    icon = "mdi:hammer-wrench";
    aliases = [
      "forge"
      "hydra"
      "continuous integration"
      "build server"
    ];
  }
  {
    id = "herald";
    name = "Herald";
    role = "ntfy notifications";
    host = "herald";
    inventoryHost = "herald";
    probeUrl = "https://herald.guildedthorn.arpa/v1/health";
    launchUrl = "https://herald.guildedthorn.arpa/";
    icon = "mdi:bell-ring-outline";
    aliases = [
      "herald"
      "notifications"
      "ntfy"
    ];
  }
  {
    id = "hound";
    name = "Hound";
    role = "Velociraptor endpoint response";
    host = "hound";
    inventoryHost = "hound";
    probeUrl = "https://hound.guildedthorn.arpa/app/index.html";
    launchUrl = "https://hound.guildedthorn.arpa/app/index.html";
    icon = "mdi:dog-side";
    aliases = [
      "hound"
      "velociraptor"
      "endpoint response"
      "endpoint security"
    ];
  }
  {
    id = "identity";
    name = "Identity";
    role = "Authentik single sign-on";
    host = "identity";
    inventoryHost = "identity";
    probeUrl = "https://identity.guildedthorn.arpa/";
    launchUrl = "https://identity.guildedthorn.arpa/";
    icon = "mdi:account-key-outline";
    aliases = [
      "identity"
      "authentik"
      "single sign on"
      "sso"
    ];
  }
  {
    id = "casita";
    name = "Casita Home Assistant";
    role = "Home automation and voice orchestration";
    host = "mitm";
    inventoryHost = "mitm";
    probeUrl = "https://mitm.guildedthorn.arpa/health/casita";
    launchUrl = "https://mitm.guildedthorn.arpa/thorn-home/0";
    icon = "mdi:home-assistant";
    aliases = [
      "casita"
      "home assistant"
      "home automation"
      "voice orchestration"
    ];
  }
  {
    id = "deck-voice";
    name = "Deck Voice";
    role = "Living-room voice satellite";
    host = "deck";
    probeUrl = "http://172.16.25.26:10701/api/health";
    launchUrl = "";
    icon = "mdi:account-voice";
    aliases = [
      "deck voice"
      "voice satellite"
      "steam deck assistant"
      "microphone"
    ];
  }
  {
    id = "ollama";
    name = "Ollama";
    role = "Casita local conversation model";
    host = "deck";
    probeUrl = "http://172.16.25.26:11434/api/tags";
    launchUrl = "";
    icon = "mdi:brain";
    aliases = [
      "ollama"
      "granite"
      "local model"
      "conversation model"
    ];
  }
  {
    id = "kokoro";
    name = "Kokoro";
    role = "Casita natural speech synthesis";
    host = "deck";
    probeUrl = "http://172.16.25.26:10202/health";
    launchUrl = "";
    icon = "mdi:account-voice-outline";
    aliases = [
      "kokoro"
      "natural voice"
      "speech synthesis"
      "text to speech"
    ];
  }
  {
    id = "opencanary";
    name = "Lure OpenCanary";
    role = "Deception and honeypot sensor";
    host = "lure";
    inventoryHost = "lure";
    probeUrl = "http://172.16.25.58:9101/health";
    launchUrl = "";
    icon = "mdi:bird";
    aliases = [
      "lure"
      "open canary"
      "opencanary"
      "honeypot"
      "deception sensor"
    ];
  }
  {
    id = "thornflix";
    name = "ThornFlix Jellyfin";
    role = "Personal media streaming";
    host = "truenas";
    probeUrl = "https://jellyfin.guildedthorn.com/";
    launchUrl = "https://jellyfin.guildedthorn.com/";
    icon = "mdi:jellyfish";
    aliases = [
      "thorn flix"
      "thornflix"
      "jellyfin"
      "media server"
    ];
  }
  {
    id = "owncast";
    name = "Owncast";
    role = "Self-hosted live streaming";
    host = "websites";
    inventoryHost = "websites";
    probeUrl = "http://172.16.25.50:8090/";
    launchUrl = "";
    icon = "mdi:broadcast";
    aliases = [
      "owncast"
      "live stream"
      "live streaming"
      "broadcast"
    ];
  }
  {
    id = "loom";
    name = "Loom";
    role = "n8n automation";
    host = "loom";
    inventoryHost = "loom";
    probeUrl = "https://loom.guildedthorn.arpa/healthz";
    launchUrl = "https://loom.guildedthorn.arpa/home/workflows";
    icon = "mdi:transit-connection-variant";
    aliases = [
      "loom"
      "n eight n"
      "n8n"
      "automation"
      "workflows"
    ];
  }
  {
    id = "proxmox";
    name = "Proxmox";
    role = "Virtualization cluster";
    host = "mac";
    inventoryHost = "mac";
    probeUrl = "https://proxmox.guildedthorn.arpa:8006/";
    launchUrl = "https://proxmox.guildedthorn.arpa:8006/";
    icon = "mdi:server";
    aliases = [
      "proxmox"
      "hypervisor"
      "virtual machines"
      "mac"
    ];
  }
  {
    id = "oracle";
    name = "Oracle";
    role = "OpenCTI threat intelligence";
    host = "oracle";
    inventoryHost = "oracle";
    probeUrl = "https://oracle.guildedthorn.arpa/";
    launchUrl = "https://oracle.guildedthorn.arpa/";
    icon = "mdi:database-search-outline";
    aliases = [
      "oracle"
      "open c t i"
      "opencti"
      "threat intelligence"
    ];
  }
  {
    id = "pixie";
    name = "Pixie";
    role = "Network boot and provisioning";
    host = "pixie";
    inventoryHost = "pixie";
    probeUrl = "http://172.16.25.53/boot.ipxe";
    launchUrl = "http://pixie.guildedthorn.arpa/boot.ipxe";
    icon = "mdi:lan-connect";
    aliases = [
      "pixie"
      "network boot"
      "netboot"
      "provisioning"
      "p x e"
      "pxe"
    ];
  }
  {
    id = "sieve";
    name = "Sieve";
    role = "Greenbone vulnerability scanner";
    host = "sieve";
    inventoryHost = "sieve";
    probeUrl = "https://sieve.guildedthorn.arpa/";
    launchUrl = "https://sieve.guildedthorn.arpa/";
    icon = "mdi:shield-search";
    aliases = [
      "sieve"
      "greenbone"
      "vulnerability scanner"
      "vulnerability management"
    ];
  }
  {
    id = "soc";
    name = "SOC";
    role = "Grafana security operations";
    host = "soc";
    inventoryHost = "soc";
    probeUrl = "https://soc.guildedthorn.arpa:3000/api/health";
    launchUrl = "https://soc.guildedthorn.arpa:3000/";
    icon = "mdi:shield-home-outline";
    aliases = [
      "soc"
      "security operations"
      "grafana"
      "siem"
    ];
  }
  {
    id = "guildedthorn";
    name = "GuildedThorn.com";
    role = "Public website";
    host = "websites";
    inventoryHost = "websites";
    probeUrl = "https://guildedthorn.com/";
    launchUrl = "https://guildedthorn.com/";
    icon = "mdi:web";
    aliases = [
      "guilded thorn"
      "guildedthorn dot com"
      "public website"
      "website"
      "websites"
    ];
  }
  {
    id = "truenas";
    name = "TrueNAS";
    role = "Storage management";
    host = "truenas";
    probeUrl = "https://truenas.guildedthorn.arpa/";
    launchUrl = "https://truenas.guildedthorn.arpa/";
    icon = "mdi:nas";
    aliases = [
      "true nas"
      "truenas"
      "nas"
      "storage server"
    ];
  }
  {
    id = "seaweedfs";
    name = "SeaweedFS";
    role = "S3 object storage";
    host = "truenas";
    probeUrl = "https://truenas.guildedthorn.arpa:30304/";
    launchUrl = "";
    icon = "mdi:database-cog-outline";
    aliases = [
      "seaweed f s"
      "seaweedfs"
      "s three"
      "s3"
      "object storage"
    ];
  }
  {
    id = "loki";
    name = "Loki";
    role = "Central log aggregation";
    host = "soc";
    inventoryHost = "soc";
    probeUrl = "http://127.0.0.1:3101/ready";
    launchUrl = "https://soc.guildedthorn.arpa:3000/explore";
    icon = "mdi:text-search";
    aliases = [
      "loki"
      "logs"
      "log service"
      "log aggregation"
    ];
  }
  {
    id = "prometheus";
    name = "Prometheus";
    role = "Metrics and alerting";
    host = "soc";
    inventoryHost = "soc";
    probeUrl = "http://127.0.0.1:9091/-/ready";
    launchUrl = "https://soc.guildedthorn.arpa:3000/d/service-health";
    icon = "mdi:chart-timeline-variant-shimmer";
    aliases = [
      "prometheus"
      "metrics"
      "monitoring"
      "alerting"
    ];
  }
]
