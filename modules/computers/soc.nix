{ config, inputs, ... }:
{
  flake.nixosConfigurations.soc = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      config.nixos.modules.thorn-core

      config.nixos.modules.services-ssh

      ({ modulesPath, ... }: { imports = [ (modulesPath + "/profiles/qemu-guest.nix") ]; })

      "${inputs.self}/hosts/soc/hardware-configuration.nix"
      "${inputs.self}/hosts/soc/disko.nix"
      "${inputs.self}/hosts/soc/networking.nix"
      "${inputs.self}/hosts/soc/secrets.nix"

      (
        { config, lib, ... }:
        let
          # SeaweedFS S3 gateway on the NAS. Loki keeps only its WAL and
          # caches on the VM disk; all chunk/index storage lives in the
          # `loki` bucket, so this VM is rebuildable without data loss.
          seaweedfsS3 = "truenas.guildedthorn.arpa:30304";

          # Hosts Prometheus scrapes for node metrics (port 9100, opened
          # fleet-wide by services-observability). A powered-off lab VM just
          # shows as down.
          fleet = [
            # "firewall" is in the flake but not deployed — pfSense is the
            # router for now; add it back here when it's wired up.
            "mac"
            "mitm"
            "nixos"
            "proxmox-guest"
            "scout"
            "soc"
            "websites"
          ];
        in
        {
          # Trust the LAN CA so Loki's S3 client can verify the SeaweedFS
          # gateway's certificate.
          security.pki.certificates = [
            (builtins.readFile "${inputs.self}/certs/ThornCloud_CA.crt")
          ];

          boot = {
            growPartition = true;
            # BIOS boot via GRUB on the whole disk. disko already registers
            # /dev/sda as a GRUB device; force a single entry so the two
            # definitions don't merge into a duplicate (mirroredBoots assert).
            loader.grub = {
              enable = true;
              devices = lib.mkForce [ "/dev/sda" ];
              efiSupport = false;
            };
            # Keep the NIC named eth0, matching the static config in
            # hosts/soc/networking.nix (same as websites).
            kernelParams = [ "net.ifnames=0" ];
          };
          services.qemuGuest.enable = true;

          services.openssh.settings = {
            PermitRootLogin = "prohibit-password";
            PasswordAuthentication = false;
          };
          # Workstation key — headless host, no other login path.
          users.users.root.openssh.authorizedKeys.keys = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIO+iFLtqnhkscz2qLK45nJVmGZIbQvIeIuW8tenAjX2p thorn@workstation"
          ];

          services.loki = {
            enable = true;
            # Lets the config reference the S3 credentials as ${ENV_VAR}
            # from the sops-templated EnvironmentFile below.
            extraFlags = [ "--config.expand-env=true" ];
            configuration = {
              auth_enabled = false;

              server.http_listen_port = 3100;

              common = {
                path_prefix = "/var/lib/loki";
                replication_factor = 1;
                ring = {
                  instance_addr = "127.0.0.1";
                  kvstore.store = "inmemory";
                };
                storage.s3 = {
                  endpoint = seaweedfsS3;
                  bucketnames = "loki";
                  region = "us-east-1";
                  access_key_id = "\${LOKI_S3_ACCESS_KEY_ID}";
                  secret_access_key = "\${LOKI_S3_SECRET_ACCESS_KEY}";
                  # HTTPS with a ThornCloud_CA cert (trusted via
                  # security.pki below). SeaweedFS doesn't do virtual-hosted
                  # bucket addressing.
                  s3forcepathstyle = true;
                };
              };

              schema_config.configs = [
                {
                  from = "2026-01-01";
                  store = "tsdb";
                  object_store = "s3";
                  schema = "v13";
                  index = {
                    prefix = "index_";
                    period = "24h";
                  };
                }
              ];

              storage_config.tsdb_shipper = {
                active_index_directory = "/var/lib/loki/tsdb-index";
                cache_location = "/var/lib/loki/tsdb-cache";
              };

              compactor = {
                working_directory = "/var/lib/loki/compactor";
                retention_enabled = true;
                delete_request_store = "s3";
              };

              limits_config = {
                retention_period = "90d";
                reject_old_samples = true;
                reject_old_samples_max_age = "168h";
              };
            };
          };
          systemd.services.loki.serviceConfig.EnvironmentFile = config.sops.templates."loki-s3.env".path;

          # Metrics stay on the VM disk — small at this fleet size, and
          # object storage for Prometheus means Thanos/Mimir complexity
          # that isn't worth it yet.
          services.prometheus = {
            enable = true;
            retentionTime = "90d";
            globalConfig.scrape_interval = "30s";
            scrapeConfigs = [
              {
                job_name = "node";
                static_configs = [
                  { targets = map (host: "${host}.guildedthorn.arpa:9100") fleet; }
                ];
              }
            ];
          };

          services.grafana = {
            enable = true;
            settings = {
              server = {
                http_addr = "0.0.0.0";
                http_port = 3000;
                domain = "soc.guildedthorn.arpa";
                enable_gzip = true;
              };
              security.admin_password = "$__file{${config.sops.secrets.grafana_admin_password.path}}";
              security.secret_key = "$__file{${config.sops.secrets.grafana_secret_key.path}}";
              analytics.reporting_enabled = false;
            };
            provision = {
              enable = true;
              datasources.settings.datasources = [
                {
                  name = "Loki";
                  type = "loki";
                  url = "http://127.0.0.1:3100";
                }
                {
                  name = "Prometheus";
                  type = "prometheus";
                  url = "http://127.0.0.1:9090";
                  isDefault = true;
                }
              ];
            };
          };
        }
      )
    ];
  };
}
