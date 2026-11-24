{ pkgs, lib }:
let
  fleet = import ../hosts/inventory.nix;
  catalog = import ../hosts/service-catalog.nix;
  rice = import ./rice.nix;
  grafana = "https://soc.guildedthorn.arpa:3000";
  link = title: url: { inherit title url; };
  services = ids: builtins.filter (service: builtins.elem service.id ids) catalog;
  bookmarks = title: entries: {
    type = "bookmarks";
    inherit title;
    groups = [ { links = entries; } ];
  };
  serviceLinks =
    ids:
    map (s: link "${s.name} · ${s.role}" s.launchUrl) (
      builtins.filter (s: s.launchUrl != "") (services ids)
    );
  site = service: {
    title = service.name;
    url = if service.launchUrl == "" then service.probeUrl else service.launchUrl;
    check-url = service.probeUrl;
    icon = service.icon;
    timeout = "5s";
    # These are reachability checks, including protected HTTP listeners.
    alt-status-codes = [
      401
      403
    ];
  };
  # Loopback checks in the SOC catalog are local to SOC, not this laptop.
  remoteServices = builtins.filter (s: !(lib.hasPrefix "http://127.0.0.1" s.probeUrl)) catalog;
  monitor = title: entries: {
    type = "monitor";
    inherit title;
    cache = "2m";
    sites = map site entries;
  };
  mediaSites = [
    {
      title = "Immich";
      url = "https://immich.guildedthorn.arpa/";
      check-url = "https://immich.guildedthorn.arpa/api/server/ping";
      icon = "si:immich";
    }
    {
      title = "Jellyfin · LAN";
      url = "https://jellyfin.guildedthorn.arpa/";
      check-url = "https://jellyfin.guildedthorn.arpa/health";
      icon = "si:jellyfin";
    }
    {
      title = "MusicGrabber";
      url = "https://musicgrabber.guildedthorn.arpa/";
      check-url = "https://musicgrabber.guildedthorn.arpa/";
      icon = "si:spotify";
    }
    {
      title = "Live Sports";
      url = "https://livesports.guildedthorn.arpa/configure";
      check-url = "https://livesports.guildedthorn.arpa/manifest.json";
      icon = "mdi:sports";
    }
    {
      title = "Wikipedia";
      url = "https://wiki.guildedthorn.arpa/";
      check-url = "https://wiki.guildedthorn.arpa/";
      icon = "mdi:books";
    }
    {
      title = "Forgejo";
      url = "https://forgejo.guildedthorn.arpa/";
      check-url = "https://forgejo.guildedthorn.arpa/api/healthz";
      icon = "si:forgejo";
    }
  ];
  dashboardLinks = bookmarks "Operations" (
    map (entry: link entry.title "${grafana}/d/${entry.uid}") [
      {
        title = "Fleet health";
        uid = "fleet-health";
      }
      {
        title = "Deployments";
        uid = "fleet-deploys";
      }
      {
        title = "Capacity";
        uid = "fleet-capacity";
      }
      {
        title = "Service health";
        uid = "service-health";
      }
      {
        title = "SOC overview";
        uid = "soc-overview";
      }
    ]
    ++ [
      (link "Explore logs and metrics" "${grafana}/explore")
      (link "Alert rules" "${grafana}/alerting/list")
    ]
  );
  hydra = {
    type = "custom-api";
    title = "Forge · recent evaluations";
    title-url = "https://forge.guildedthorn.arpa/jobset/thornixos/main";
    cache = "5m";
    url = "https://forge.guildedthorn.arpa/jobset/thornixos/main/evals";
    headers.Accept = "application/json";
    template = ''
      <ul class="list list-gap-10 collapsible-container" data-collapse-after="3">
      {{ range .JSON.Array "evals" }}
        <li class="flex justify-between gap-10">
          <a class="color-primary" href="https://forge.guildedthorn.arpa/eval/{{ .Int "id" }}">Evaluation #{{ .Int "id" }}</a>
          {{ if eq (.Int "hasnewbuilds") 1 }}<span class="color-highlight">New builds</span>{{ else }}<span>No new builds</span>{{ end }}
        </li>
      {{ else }}<li>No evaluations returned by Forge.</li>{{ end }}
      </ul>
      <p class="size-h6 margin-top-15">Evaluation activity; deployment status lives in Fleet Deployments.</p>
    '';
  };
  attention = (monitor "Lab reachability · failures" remoteServices) // {
    show-failing-only = true;
  };
  dailyLinks = bookmarks "Your lab" (
    [
      (link "Immich" "https://immich.guildedthorn.arpa/")
      (link "Jellyfin" "https://jellyfin.guildedthorn.arpa/")
      (link "MusicGrabber" "https://musicgrabber.guildedthorn.arpa/")
      (link "Live Sports" "https://livesports.guildedthorn.arpa/configure")
      (link "Wikipedia" "https://wiki.guildedthorn.arpa/")
      (link "Forgejo" "https://forgejo.guildedthorn.arpa/")
    ]
    ++ serviceLinks [
      "vault"
      "miniflux"
      "casita"
      "loom"
      "forge"
      "soc"
    ]
  );
  graniteLinks = bookmarks "Granite · NixOS storage" [
    (link "Storage, ZFS, and drive health" "${grafana}/d/fleet-health?var-host=granite.guildedthorn.arpa:9100")
    (link "Disk capacity" "${grafana}/d/fleet-capacity?var-host=granite.guildedthorn.arpa:9100")
    (link "Services and backup evidence" "${grafana}/d/service-health")
    (link "Granite configuration" "https://github.com/GuildedThorn/ThornixOS/tree/main/hosts/granite")
  ];
  small = widgets: {
    size = "small";
    inherit widgets;
  };
  full = widgets: {
    size = "full";
    inherit widgets;
  };
  notice = {
    type = "html";
    title = "Reading this dashboard";
    source = ''
      <p>Checks run from this workstation. Away from home, connect the lab VPN before interpreting failures.</p>
      <p class="margin-top-15">Login pages and HTTP 401/403 count as reachable, not proof of application or backup health. Use Grafana for alerts, restore evidence, and deployment state.</p>
    '';
  };
  everydayLinks = bookmarks "Everyday" [
    (link "Maps and directions" "https://www.google.com/maps")
    (link "Chicago weather and warnings" "https://www.weather.gov/lot/")
    (link "FlightAware" "https://www.flightaware.com/")
    (link "Wikipedia" "https://en.wikipedia.org/")
    (link "Internet Archive" "https://archive.org/")
  ];
in
{
  inherit
    attention
    dailyLinks
    hydra
    everydayLinks
    ;
  assets = pkgs.linkFarm "thornix-glance-assets" [
    {
      name = "thornix.svg";
      path = rice.branding.svg pkgs;
    }
    {
      name = "thornix.css";
      path = pkgs.writeText "thornix-glance.css" ''
        :root { --border-radius: ${toString rice.geometry.radiusMedium}px; }
        body { font-family: "${rice.fonts.sans}", system-ui, sans-serif; }
        .widget-content { border-color: #${rice.colors.surface1}; }
        a:focus-visible { outline: 2px solid #${rice.colors.mauve}; outline-offset: 4px; }
        .lab-fleet { display: grid; grid-template-columns: repeat(auto-fit, minmax(210px, 1fr)); gap: 12px; }
        .lab-host { padding: 12px; border: 1px solid #${rice.colors.surface1}; border-radius: 10px; }
        .lab-host small { display: block; color: #${rice.colors.subtext0}; margin-top: 5px; }
      '';
    }
  ];
  theme = {
    background-color = "240 21 15";
    primary-color = "267 84 81";
    positive-color = "115 54 76";
    negative-color = "343 81 75";
    contrast-multiplier = 1.1;
    custom-css-file = "/assets/thornix.css";
  };
  branding = {
    app-name = "Thornix · Home Lab";
    logo-url = "/assets/thornix.svg";
    favicon-url = "/assets/thornix.svg";
  };
  pages = [
    {
      name = "Local";
      columns = [
        (small [
          {
            type = "weather";
            title = "Alsip";
            location = "Alsip";
            units = "imperial";
          }
          (bookmarks "Getting around Chicago" [
            (link "Illinois road conditions" "https://www.gettingaroundillinois.com/")
            (link "CTA service alerts" "https://www.transitchicago.com/alerts/")
            (link "Metra service alerts" "https://metra.com/service-alerts")
            (link "Flight tracking" "https://www.flightaware.com/")
          ])
        ])
        (full [
          {
            type = "custom-api";
            title = "Alsip area · active weather alerts";
            title-url = "https://www.weather.gov/lot/";
            cache = "10m";
            url = "https://api.weather.gov/alerts/active?point=41.67,-87.74";
            headers = {
              User-Agent = "ThornixOS Glance (https://github.com/GuildedThorn/ThornixOS)";
              Accept = "application/geo+json";
            };
            template = ''
              <ul class="list list-gap-20">
              {{ range .JSON.Array "features" }}
                <li>
                  <p class="color-highlight size-h3">{{ .String "properties.event" }}</p>
                  <p class="margin-top-10">{{ .String "properties.headline" }}</p>
                  <p class="size-h6 margin-top-10">Severity: {{ .String "properties.severity" }} · {{ .String "properties.areaDesc" }}</p>
                </li>
              {{ else }}
                <li>No active NWS alerts returned for the Alsip area.</li>
              {{ end }}
              </ul>
              <p class="size-h6 margin-top-15">Source: National Weather Service · approximate Alsip location · refreshed every 10 minutes.</p>
            '';
          }
          (bookmarks "Outside and around town" [
            (link "Chicago weather radar" "https://radar.weather.gov/")
            (link "Cook County forest preserves" "https://fpdcc.com/")
            (link "Chicago Public Library events" "https://chipublib.bibliocommons.com/v2/events")
            (link "Adler Planetarium" "https://www.adlerplanetarium.org/")
          ])
        ])
      ];
    }
    {
      name = "Discover";
      columns = [
        (small [
          (bookmarks "Learn and explore" [
            (link "MIT OpenCourseWare" "https://ocw.mit.edu/")
            (link "Khan Academy" "https://www.khanacademy.org/")
            (link "Project Gutenberg · books" "https://www.gutenberg.org/")
            (link "Smithsonian Open Access" "https://www.si.edu/openaccess")
            (link "NASA astronomy picture of the day" "https://apod.nasa.gov/apod/")
            (link "Radio Garden · world radio" "https://radio.garden/")
          ])
          (bookmarks "Make and create" [
            (link "Printables · 3D models" "https://www.printables.com/")
            (link "Instructables · projects" "https://www.instructables.com/")
            (link "Blender Studio · training" "https://studio.blender.org/training/")
          ])
        ])
        (full [
          {
            type = "rss";
            title = "Space and exploration";
            cache = "3h";
            limit = 10;
            collapse-after = 5;
            feeds = [
              {
                url = "https://www.nasa.gov/news-release/feed/";
                title = "NASA";
              }
            ];
          }
          {
            type = "rss";
            title = "Beyond technology";
            cache = "3h";
            limit = 12;
            collapse-after = 6;
            feeds = [
              {
                url = "https://www.sciencedaily.com/rss/top/science.xml";
                title = "ScienceDaily";
              }
              {
                url = "https://www.nature.com/nature.rss";
                title = "Nature";
              }
            ];
          }
        ])
      ];
    }
    {
      name = "Lab";
      slug = "services"; # Preserve the old Services URL.
      columns = [
        (small [
          dashboardLinks
          graniteLinks
          notice
        ])
        (full [
          attention
          (monitor "Core infrastructure" (services [
            "proxmox"
            "atlas"
            "identity"
            "anvil"
            "resolver-primary"
            "resolver-secondary"
            "vault"
          ]))
          (monitor "Development and automation" (services [
            "forge"
            "loom"
            "herald"
            "searxng"
            "miniflux"
            "rss-bridge"
            "casita"
          ]))
          {
            type = "monitor";
            title = "Photos, media, and source code";
            cache = "2m";
            sites = mediaSites;
          }
          (monitor "Security operations" (services [
            "soc"
            "casebook"
            "hound"
            "oracle"
            "sieve"
            "opencanary"
          ]))
        ])
        (small [
          (bookmarks "Security workbench" (serviceLinks [
            "casebook"
            "hound"
            "oracle"
            "sieve"
            "hashtopolis"
          ]))
          (monitor "Voice and public services" (services [
            "deck-voice"
            "ollama"
            "kokoro"
            "owncast"
            "guildedthorn"
            "thornflix"
          ]))
        ])
      ];
    }
    {
      name = "Develop";
      columns = [
        (small [
          (bookmarks "Build and ship" [
            (link "ThornixOS source" "https://github.com/GuildedThorn/ThornixOS")
            (link "Pull requests" "https://github.com/GuildedThorn/ThornixOS/pulls")
            (link "GitHub Actions" "https://github.com/GuildedThorn/ThornixOS/actions")
            (link "Hydra jobset" "https://forge.guildedthorn.arpa/jobset/thornixos/main")
            (link "Forgejo" "https://forgejo.guildedthorn.arpa/")
            (link "Reposilite" "https://reposilite.guildedthorn.arpa/")
            (link "Nix packages" "https://search.nixos.org/packages?channel=unstable")
            (link "NixOS options" "https://search.nixos.org/options?channel=unstable")
            (link "Home Manager options" "https://nix-community.github.io/home-manager/options.xhtml")
          ])
          dashboardLinks
        ])
        (full [
          hydra
          {
            type = "repository";
            repository = "GuildedThorn/ThornixOS";
            pull-requests-limit = 8;
            issues-limit = 5;
            commits-limit = 8;
          }
        ])
        (small [
          {
            type = "releases";
            title = "Lab upstreams";
            cache = "12h";
            show-source-icon = true;
            collapse-after = 6;
            repositories = [
              "glanceapp/glance"
              "immich-app/immich"
              "jellyfin/jellyfin"
              "goauthentik/authentik"
              "n8n-io/n8n"
              "netbox-community/netbox"
            ];
          }
          {
            type = "rss";
            title = "NixOS updates";
            cache = "6h";
            limit = 6;
            feeds = [
              {
                url = "https://nixos.org/blog/announcements-rss.xml";
                title = "NixOS";
              }
            ];
          }
        ])
      ];
    }
    {
      name = "Media";
      columns = [
        (small [
          graniteLinks
          (bookmarks "Photos and playback" [
            (link "Immich · photo library" "https://immich.guildedthorn.arpa/")
            (link "Jellyfin · media library" "https://jellyfin.guildedthorn.arpa/")
            (link "Seerr · requests" "https://seerr.guildedthorn.arpa/")
          ])
          (bookmarks "Library management" [
            (link "Sonarr · series" "https://sonarr.guildedthorn.arpa/")
            (link "Radarr · movies" "https://radarr.guildedthorn.arpa/")
            (link "Prowlarr · indexers" "https://prowlarr.guildedthorn.arpa/")
            (link "qBittorrent · downloads" "https://qbittorrent.guildedthorn.arpa/")
          ])
        ])
        (full [
          {
            type = "monitor";
            title = "Photo and media availability";
            cache = "2m";
            sites = builtins.filter (s: s.title != "Forgejo") mediaSites;
          }
          {
            type = "custom-api";
            title = "Immich server";
            title-url = "https://immich.guildedthorn.arpa/";
            url = "https://immich.guildedthorn.arpa/api/server/version";
            cache = "1h";
            template = ''
              <p class="color-highlight size-h3">{{ .JSON.Int "major" }}.{{ .JSON.Int "minor" }}.{{ .JSON.Int "patch" }}</p>
              <p class="margin-top-15">Installed Immich version. Upstream releases are listed on Develop.</p>
            '';
          }
          {
            type = "html";
            title = "Library operations";
            source = ''
              <p>Photos: use Immich for uploads, albums, sharing, and job queues.</p>
              <p class="margin-top-15">Media: request in Seerr, inspect Sonarr/Radarr queues, then check indexers and downloads.</p>
              <p class="margin-top-15"><a class="color-primary" href="${grafana}/d/service-health">Storage and backup evidence in Grafana →</a></p>
            '';
          }
        ])
      ];
    }
    {
      name = "Fleet";
      columns = [
        (small [
          dashboardLinks
          notice
        ])
        (full [
          {
            type = "html";
            title = "Fleet inventory";
            source =
              ''<div class="lab-fleet">''
              + lib.concatStringsSep "\n" (
                lib.mapAttrsToList (name: host: ''
                  <div class="lab-host">
                  <a class="color-primary" href="${grafana}/d/fleet-health?var-host=${host.fqdn}:9100">${name}</a>
                    <small>${host.role} · ${host.class}</small>
                    <small>${if host.address == null then "Roaming / no fixed address" else host.address}</small>
                    <small>${
                      if host.deployment.enable then "Production deployment" else "Manual deployment"
                    } · telemetry: ${host.monitoring.mode}</small>
                  </div>
                '') (lib.filterAttrs (_: host: host.class != "template") fleet)
              )
              + "</div>";
          }
          attention
        ])
      ];
    }
  ];
}
